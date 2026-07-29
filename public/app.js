(function () {
  const serverUrl = window.location.origin.replace(/^http/, 'ws');
  const voice = new MeshVoice(serverUrl);

  const $ = (id) => document.getElementById(id);
  const statusEl = $('status');
  const peerListEl = $('peerList');

  function setStatus(text, online) {
    statusEl.textContent = text;
    statusEl.className = 'status ' + (online ? 'online' : 'offline');
  }

  function updatePeerList() {
    const ids = Array.from(voice.peerConnections.keys());
    peerListEl.innerHTML = ids.length
      ? ids.map((pid) => `<div class="peer">${pid.slice(0, 8)}…</div>`).join('')
      : '<div class="peer" style="color:#666">No peers connected</div>';
  }

  $('connectBtn').addEventListener('click', async () => {
    const sessionId = $('sessionId').value.trim();
    const roomId = $('roomId').value.trim() || 'default';

    if (!sessionId) { setStatus('Enter a Session ID first', false); return; }

    $('connectBtn').disabled = true;

    try {
      await voice.init();
      await voice.startMic();

      voice.onConnected = () => {
        setStatus('Connected – waiting for peers…', true);
        $('connectBtn').disabled = true;
        $('disconnectBtn').disabled = false;
      };

      voice.onDisconnected = () => {
        setStatus('Disconnected', false);
        $('connectBtn').disabled = false;
        $('disconnectBtn').disabled = true;
      };

      voice.onPeerJoined = (pid) => {
        setStatus(`Peer joined: ${pid.slice(0, 8)}…`, true);
        updatePeerList();
      };

      voice.onPeerLeft = (pid) => {
        setStatus(`Peer left: ${pid.slice(0, 8)}…`, true);
        updatePeerList();
      };

      voice.onRoomState = (peers) => {
        setStatus(`Connected – ${peers.length} peer(s) in room`, true);
        updatePeerList();
      };

      voice.connect(sessionId, roomId);
    } catch (e) {
      setStatus('Error: ' + e.message, false);
      $('connectBtn').disabled = false;
    }
  });

  $('disconnectBtn').addEventListener('click', () => {
    voice.disconnect();
    setStatus('Disconnected', false);
    $('connectBtn').disabled = false;
    $('disconnectBtn').disabled = true;
    peerListEl.innerHTML = '';
  });

  $('volume').addEventListener('input', (e) => {
    voice.setMasterVolume(parseFloat(e.target.value));
  });

  const params = new URLSearchParams(window.location.search);
  if (params.get('session')) $('sessionId').value = params.get('session');
  if (params.get('room')) $('roomId').value = params.get('room');

  setStatus('Enter your Session ID and click Connect', false);
})();
