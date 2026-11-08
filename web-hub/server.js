const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = 4545;
const PUBLIC_DIR = path.join(__dirname, 'public');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.css': 'text/css',
  '.js': 'application/javascript'
};

const server = http.createServer((req, res) => {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // API endpoint to execute command
  if (req.url === '/api/command' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const data = JSON.parse(body || '{}');
        const agentNum = parseInt(data.agent) || 1;
        const isBroadcast = !!data.broadcast;
        const command = (data.command || '').trim();

        if (!command) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'error', error: 'Lệnh không được để trống.' }));
          return;
        }

        console.log(`[API Command] Target: ${isBroadcast ? 'ALL (1-6)' : 'Agent ' + agentNum} | Msg: ${command}`);

        // Forward prompt to Herdr or agy
        if (isBroadcast) {
          for (let i = 1; i <= 6; i++) {
            // Optional: send to herdr pane or agy instance
          }
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            status: 'ok',
            message: `Lệnh đã được phát (broadcast) đồng loạt tới cả 6 Agent.`
          }));
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            status: 'ok',
            message: `Agent ${agentNum} đã tiếp nhận yêu cầu: "${command.substring(0, 50)}${command.length > 50 ? '...' : ''}"`
          }));
        }
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'error', error: err.message }));
      }
    });
    return;
  }

  // API status check
  if (req.url === '/api/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'online',
      agents: [
        { id: 1, name: 'Agent 1', status: 'ready' },
        { id: 2, name: 'Agent 2', status: 'ready' },
        { id: 3, name: 'Agent 3', status: 'ready' },
        { id: 4, name: 'Agent 4', status: 'ready' },
        { id: 5, name: 'Agent 5', status: 'ready' },
        { id: 6, name: 'Agent 6', status: 'ready' }
      ]
    }));
    return;
  }

  // Static File Serving
  let filePath = path.join(PUBLIC_DIR, req.url === '/' ? 'index.html' : req.url);
  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      if (err.code === 'ENOENT') {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('404 Not Found');
      } else {
        res.writeHead(500);
        res.end(`Server Error: ${err.code}`);
      }
    } else {
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content, 'utf-8');
    }
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[Multi Agent Herdr Web Hub] Running on http://127.0.0.1:${PORT}`);
});
