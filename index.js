const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');
const path = require('path');

const PORT = process.env.PORT || 3000;

const app = express();
app.use(express.json());

app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  next();
});

const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const rooms = new Map();
const peerSockets = new Map();

function broadcastToRoom(roomId, message, excludeSessionId) {
  const room = rooms.get(roomId);
  if (!room) return;
  const raw = typeof message === 'string' ? message : JSON.stringify(message);
  for (const [sid, peer] of room) {
    if (sid !== excludeSessionId && peer.ws && peer.ws.readyState === 1) {
      peer.ws.send(raw);
    }
  }
}

function getOrCreateRoom(roomId) {
  if (!rooms.has(roomId)) rooms.set(roomId, new Map());
  return rooms.get(roomId);
}

// --- HTTP endpoints (called by Roblox server) ---

app.post('/api/session/register', (req, res) => {
  const { sessionId, robloxUserId, roomId } = req.body || {};
  if (!sessionId || !roomId) {
    return res.status(400).json({ ok: false, error: 'sessionId and roomId required' });
  }
  const room = getOrCreateRoom(roomId);
  if (!room.has(sessionId)) {
    room.set(sessionId, { ws: null, positions: null });
  }
  console.log(`[HTTP] register  session=${sessionId.slice(0,8)}…  room=${roomId.slice(0,8)}…  user=${robloxUserId || '?'}`);
  res.json({ ok: true });
});

app.post('/api/session/unregister', (req, res) => {
  const { sessionId } = req.body || {};
  if (!sessionId) return res.status(400).json({ ok: false, error: 'sessionId required' });

  for (const [roomId, room] of rooms) {
    if (room.has(sessionId)) {
      room.delete(sessionId);
      if (room.size === 0) rooms.delete(roomId);
      broadcastToRoom(roomId, { type: 'peer-left', peerId: sessionId }, null);
      break;
    }
  }
  peerSockets.delete(sessionId);
  console.log(`[HTTP] unregister  session=${sessionId.slice(0,8)}…`);
  res.json({ ok: true });
});

app.post('/api/positions/update', (req, res) => {
  const { roomId, positions } = req.body || {};
  if (!roomId || !positions) return res.status(400).json({ ok: false, error: 'roomId and positions required' });

  const room = rooms.get(roomId);
  if (!room) return res.json({ ok: true, count: 0 });

  for (const pos of positions) {
    const peer = room.get(pos.sessionId);
    if (peer) {
      peer.positions = {
        x: pos.x, y: pos.y, z: pos.z,
        lookX: pos.lookX, lookY: pos.lookY, lookZ: pos.lookZ,
        rightX: pos.rightX, rightY: pos.rightY, rightZ: pos.rightZ,
        upX: pos.upX, upY: pos.upY, upZ: pos.upZ,
      };
    }
  }

  const posList = [];
  for (const [sid, peer] of room) {
    if (peer.positions) {
      posList.push({ sessionId: sid, ...peer.positions });
    }
  }

  if (posList.length > 0) {
    const msg = JSON.stringify({ type: 'position-update', positions: posList });
    for (const [, peer] of room) {
      if (peer.ws && peer.ws.readyState === 1) {
        peer.ws.send(msg);
      }
    }
  }

  res.json({ ok: true, count: positions.length });
});

app.get('/api/health', (req, res) => {
  res.json({ ok: true, rooms: rooms.size, peers: peerSockets.size });
});

app.use(express.static(path.join(__dirname, 'public')));

// --- WebSocket (signaling + position relay to browsers) ---

wss.on('connection', (ws) => {
  let sessionId = null;
  let roomId = null;

  const send = (data) => {
    if (ws.readyState === 1) ws.send(typeof data === 'string' ? data : JSON.stringify(data));
  };

  ws.on('message', async (raw) => {
    try {
      const msg = JSON.parse(raw);

      switch (msg.type) {
        case 'join': {
          sessionId = msg.sessionId;
          roomId = msg.roomId;
          if (!sessionId || !roomId) {
            send({ type: 'error', message: 'Missing sessionId or roomId' });
            return;
          }
          const room = getOrCreateRoom(roomId);
          const existing = room.get(sessionId);
          if (existing && existing.ws && existing.ws !== ws) {
            try { existing.ws.close(); } catch (_) {}
          }
          room.set(sessionId, { ws, positions: (existing && existing.positions) || null });
          peerSockets.set(sessionId, ws);

          const peers = [];
          for (const sid of room.keys()) {
            if (sid !== sessionId) peers.push(sid);
          }
          send({ type: 'room-state', yourId: sessionId, peers });

          broadcastToRoom(roomId, { type: 'peer-joined', peerId: sessionId }, sessionId);

          const posList = [];
          for (const [sid, peer] of room) {
            if (sid !== sessionId && peer.positions) {
              posList.push({ sessionId: sid, ...peer.positions });
            }
          }
          if (posList.length > 0) {
            send({ type: 'position-update', positions: posList });
          }

          console.log(`[WS] join  ${sessionId.slice(0,8)}…  room ${roomId.slice(0,8)}…  (${room.size} peers)`);
          break;
        }

        case 'offer':
        case 'answer': {
          if (!msg.targetPeerId || !msg.sdp) break;
          const target = peerSockets.get(msg.targetPeerId);
          if (target && target.readyState === 1) {
            target.send(JSON.stringify({ type: msg.type, peerId: sessionId, sdp: msg.sdp }));
          }
          break;
        }

        case 'ice-candidate': {
          if (!msg.targetPeerId || !msg.candidate) break;
          const target = peerSockets.get(msg.targetPeerId);
          if (target && target.readyState === 1) {
            target.send(JSON.stringify({ type: 'ice-candidate', peerId: sessionId, candidate: msg.candidate }));
          }
          break;
        }

        case 'ping':
          send({ type: 'pong' });
          break;
      }
    } catch (e) {
      send({ type: 'error', message: 'Invalid message' });
    }
  });

  ws.on('close', () => {
    if (sessionId && roomId) {
      const room = rooms.get(roomId);
      if (room) {
        room.delete(sessionId);
        if (room.size === 0) rooms.delete(roomId);
        broadcastToRoom(roomId, { type: 'peer-left', peerId: sessionId }, sessionId);
      }
      peerSockets.delete(sessionId);
      console.log(`[WS] leave  ${sessionId.slice(0,8)}…  room ${roomId.slice(0,8)}…`);
    }
  });
});

server.listen(PORT, () => {
  console.log(`RovC Voice Server running on :${PORT}`);
});
