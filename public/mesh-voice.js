class MeshVoice {
  constructor(serverUrl, iceConfig) {
    this.serverUrl = serverUrl;
    this.iceConfig = iceConfig || {};
    this.iceServers = {
      iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:stun1.l.google.com:19302' },
      ],
    };

    if (this.iceConfig.turnUrl && this.iceConfig.turnUsername && this.iceConfig.turnCredential) {
      this.iceServers.iceServers.push({
        urls: this.iceConfig.turnUrl,
        username: this.iceConfig.turnUsername,
        credential: this.iceConfig.turnCredential,
      });
    }
    if (this.iceConfig.forceRelay) {
      this.iceServers.iceTransportPolicy = 'relay';
    }

    this.ws = null;
    this.sessionId = null;
    this.roomId = null;
    this.audioContext = null;
    this.localStream = null;

    this.peerConnections = new Map();
    this.remoteAudio = new Map();

    this.myPosition = { x: 0, y: 0, z: 0 };
    this.myOrientation = {
      lookX: 0, lookY: 0, lookZ: -1,
      rightX: 1, rightY: 0, rightZ: 0,
      upX: 0, upY: 1, upZ: 0,
    };

    this._masterGain = null;

    this.onConnected = null;
    this.onDisconnected = null;
    this.onPeerJoined = null;
    this.onPeerLeft = null;
    this.onRoomState = null;

    this._shouldReconnect = true;
    this._reconnectAttempts = 0;
    this._maxReconnect = 15;
  }

  // --- Public API ---

  async init() {
    if (!this.audioContext) {
      this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }
    if (this.audioContext.state === 'suspended') {
      await this.audioContext.resume();
    }
    if (!this._masterGain) {
      this._masterGain = this.audioContext.createGain();
      this._masterGain.gain.value = 1;
      this._masterGain.connect(this.audioContext.destination);
    }
  }

  async startMic() {
    this.localStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });
  }

  connect(sessionId, roomId) {
    this.sessionId = sessionId;
    this.roomId = roomId;
    this._shouldReconnect = true;
    this._reconnectAttempts = 0;
    this._connectWS();
  }

  disconnect() {
    this._shouldReconnect = false;
    this._closeWS();
    this._closeAllPeers();
    if (this.localStream) {
      this.localStream.getTracks().forEach((t) => t.stop());
      this.localStream = null;
    }
  }

  setMasterVolume(v) {
    if (this._masterGain) this._masterGain.gain.value = Math.max(0, Math.min(1, v));
  }

  setPosition(x, y, z) {
    this.myPosition.x = x;
    this.myPosition.y = y;
    this.myPosition.z = z;
  }

  setOrientation(lookX, lookY, lookZ, rightX, rightY, rightZ, upX, upY, upZ) {
    this.myOrientation.lookX = lookX;
    this.myOrientation.lookY = lookY;
    this.myOrientation.lookZ = lookZ;
    this.myOrientation.rightX = rightX;
    this.myOrientation.rightY = rightY;
    this.myOrientation.rightZ = rightZ;
    this.myOrientation.upX = upX;
    this.myOrientation.upY = upY;
    this.myOrientation.upZ = upZ;
  }

  // --- Internal ---

  _connectWS() {
    if (this.ws) this._closeWS();

    this.ws = new WebSocket(this.serverUrl);

    this.ws.onopen = () => {
      this._reconnectAttempts = 0;
      this.ws.send(JSON.stringify({
        type: 'join',
        sessionId: this.sessionId,
        roomId: this.roomId,
      }));
      if (this.onConnected) this.onConnected();
    };

    this.ws.onmessage = (e) => this._onWSMessage(e);

    this.ws.onclose = () => {
      this.ws = null;
      if (this._shouldReconnect && this._reconnectAttempts < this._maxReconnect) {
        this._reconnectAttempts++;
        const delay = Math.min(1000 * Math.pow(2, this._reconnectAttempts - 1), 15000);
        setTimeout(() => this._connectWS(), delay);
      }
      if (this.onDisconnected) this.onDisconnected();
    };

    this.ws.onerror = () => {};
  }

  _closeWS() {
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.close();
      this.ws = null;
    }
  }

  async _onWSMessage(e) {
    try {
      const msg = JSON.parse(e.data);

      switch (msg.type) {
        case 'room-state': {
          for (const pid of msg.peers) {
            await this._ensurePeer(pid, true);
          }
          if (this.onRoomState) this.onRoomState(msg.peers);
          break;
        }

        case 'peer-joined': {
          await this._ensurePeer(msg.peerId, true);
          if (this.onPeerJoined) this.onPeerJoined(msg.peerId);
          break;
        }

        case 'peer-left': {
          this._closePeer(msg.peerId);
          if (this.onPeerLeft) this.onPeerLeft(msg.peerId);
          break;
        }

        case 'offer': {
          if (!this.peerConnections.has(msg.peerId)) {
            await this._ensurePeer(msg.peerId, false);
          }
          const pc = this.peerConnections.get(msg.peerId);
          if (!pc) break;

          const desc = new RTCSessionDescription(msg.sdp);

          if (pc.signalingState !== 'stable') {
            if (this.sessionId < msg.peerId) {
              await pc.setLocalDescription({ type: 'rollback' });
              await pc.setRemoteDescription(desc);
              const answer = await pc.createAnswer();
              await pc.setLocalDescription(answer);
              this._wsSend({ type: 'answer', targetPeerId: msg.peerId, sdp: answer });
            }
          } else {
            await pc.setRemoteDescription(desc);
            const answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            this._wsSend({ type: 'answer', targetPeerId: msg.peerId, sdp: answer });
          }
          break;
        }

        case 'answer': {
          const pc = this.peerConnections.get(msg.peerId);
          if (pc && pc.signalingState === 'have-local-offer') {
            await pc.setRemoteDescription(new RTCSessionDescription(msg.sdp));
          }
          break;
        }

        case 'ice-candidate': {
          const pc = this.peerConnections.get(msg.peerId);
          if (pc && msg.candidate) {
            await pc.addIceCandidate(new RTCIceCandidate(msg.candidate));
          }
          break;
        }

        case 'position-update': {
          this._applyPositions(msg.positions || []);
          break;
        }
      }
    } catch (err) {
      console.warn('[MeshVoice] WS message error:', err);
    }
  }

  async _ensurePeer(peerId, initiate) {
    if (this.peerConnections.has(peerId)) return;

    const pc = new RTCPeerConnection(this.iceServers);
    this.peerConnections.set(peerId, pc);

    this._setupAudioForPeer(peerId);

    if (this.localStream) {
      for (const track of this.localStream.getTracks()) {
        pc.addTrack(track, this.localStream);
      }
    }

    pc.onicecandidate = (e) => {
      if (e.candidate) {
        this._wsSend({
          type: 'ice-candidate',
          targetPeerId: peerId,
          candidate: e.candidate.toJSON(),
        });
      }
    };

    pc.ontrack = (e) => {
      const audio = this.remoteAudio.get(peerId);
      if (!audio) return;
      if (audio.source) audio.source.disconnect();
      const stream = e.streams[0];
      if (!stream) return;
      audio.source = this.audioContext.createMediaStreamSource(stream);
      audio.source.connect(audio.panner);
    };

    pc.onconnectionstatechange = () => {
      const state = pc.connectionState;
      if (state === 'failed' || state === 'disconnected') {
        console.log('[MeshVoice] peer disconnected:', peerId.slice(0, 8));
        this.peerConnections.delete(peerId);
        const audio = this.remoteAudio.get(peerId);
        if (audio) {
          if (audio.source) audio.source.disconnect();
          audio.panner.disconnect();
          audio.gain.disconnect();
          this.remoteAudio.delete(peerId);
        }
      }
    };

    if (initiate) {
      try {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        this._wsSend({ type: 'offer', targetPeerId: peerId, sdp: offer });
      } catch (e) {
        console.warn('[MeshVoice] createOffer failed:', e);
      }
    }
  }

  _setupAudioForPeer(peerId) {
    const panner = this.audioContext.createPanner();
    panner.panningModel = 'HRTF';
    panner.distanceModel = 'inverse';
    panner.refDistance = 3;
    panner.maxDistance = 50;
    panner.rolloffFactor = 1.5;
    panner.coneInnerAngle = 360;
    panner.coneOuterAngle = 0;
    panner.coneOuterGain = 0;

    const gain = this.audioContext.createGain();
    gain.gain.value = 1;

    panner.positionX.value = 0;
    panner.positionY.value = 1000;
    panner.positionZ.value = 0;

    panner.connect(gain);
    gain.connect(this._masterGain || this.audioContext.destination);

    this.remoteAudio.set(peerId, { panner, gain, source: null });
  }

  _closePeer(peerId) {
    const pc = this.peerConnections.get(peerId);
    if (pc) {
      pc.close();
      this.peerConnections.delete(peerId);
    }
    const audio = this.remoteAudio.get(peerId);
    if (audio) {
      if (audio.source) audio.source.disconnect();
      audio.panner.disconnect();
      audio.gain.disconnect();
      this.remoteAudio.delete(peerId);
    }
  }

  _closeAllPeers() {
    for (const pid of this.peerConnections.keys()) {
      this._closePeer(pid);
    }
  }

  _wsSend(data) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  _applyPositions(positions) {
    const f = this.myOrientation;
    const pos = this.myPosition;

    for (const p of positions) {
      if (p.sessionId === this.sessionId) continue;

      const dx = p.x - pos.x;
      const dy = p.y - pos.y;
      const dz = p.z - pos.z;

      const localX = dx * f.rightX + dy * f.rightY + dz * f.rightZ;
      const localY = dx * f.upX    + dy * f.upY    + dz * f.upZ;
      const localZ = -(dx * f.lookX + dy * f.lookY + dz * f.lookZ);

      const audio = this.remoteAudio.get(p.sessionId);
      if (audio) {
        audio.panner.positionX.value = localX;
        audio.panner.positionY.value = localY;
        audio.panner.positionZ.value = localZ;
      }
    }
  }
}
