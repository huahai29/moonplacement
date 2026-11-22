import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../_build/workbench/', import.meta.url));
const port = Number(process.env.MOONPLACEMENT_WEB_PORT || 4174);
const types = { '.mjs': 'text/javascript', '.css': 'text/css', '.html': 'text/html',
  '.json': 'application/json', '.csv': 'text/csv', '.gbr': 'text/plain' };
createServer(async (request, response) => {
  const path = new URL(request.url, 'http://localhost').pathname.replace(/^\//, '') || 'index.html';
  if (!/^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(path) ||
      path.split('/').some(part => part === '.' || part === '..')) {
    response.writeHead(404).end();
    return;
  }
  const type = types[extname(path)];
  const file = root + path.replaceAll('/', sep);
  try {
    if (!type || !(await stat(file)).isFile()) {
      response.writeHead(404).end();
      return;
    }
  } catch {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { 'Content-Type': type + '; charset=utf-8' });
  if (request.method === 'HEAD') response.end();
  else createReadStream(file).on('error', () => response.destroy()).pipe(response);
}).listen(port, '127.0.0.1', () => console.log(`http://127.0.0.1:${port}/`));
