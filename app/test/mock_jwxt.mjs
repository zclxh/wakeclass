import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixture = fs.readFileSync(path.join(__dirname, 'fixtures', 'zf.html'), 'utf8');
const PORT = Number(process.env.MOCK_PORT) || 8788;
const sessions = new Map();

const loginPage = (error = '') => `<!doctype html><html><head><meta charset="utf-8"><title>登录</title></head>
<body>
<h2>教务系统用户登录</h2>
${error ? `<div class="error">${error}</div>` : ''}
<form method="post" action="/jwglxt/xtgl/login_slogin.html">
  <input type="hidden" name="csrftoken" value="mock-csrf-token">
  <label>用户名 <input id="yhm" name="yhm" type="text"></label>
  <label>密码 <input id="mm" name="mm" type="password"></label>
  <button type="submit">登录</button>
</form>
</body></html>`;

const dashboard = `<!doctype html><html><head><meta charset="utf-8"><title>教务系统</title></head><body>
<div>欢迎使用正方教务系统</div>
<a href="/jwglxt/kbcx/xskbcx?gnmkdm=N2151">学生课表查询</a>
<a href="/jwglxt/xtgl/index_initMenu.html">首页</a>
</body></html>`;

const schedulePage = `<!doctype html><html><head><meta charset="utf-8"><title>学生课表</title></head><body>
<div class="tools">
  <select name="xnm"><option value="2025">2025-2026</option><option value="2026" selected>2026-2027</option></select>
  <select name="xqm"><option value="12">第二学期</option><option value="3" selected>第一学期</option></select>
</div>
${fixture.replace(/^[\s\S]*<body>|<\/body>[\s\S]*$/gi, '')}
</body></html>`;

const qzLoginPage = (error = '') => `<!doctype html><html><head><meta charset="utf-8"><title>强智教务</title></head>
<body>
<h2>强智科技教务网络管理系统</h2>
${error ? `<div class="error">${error}</div>` : ''}
<form method="post" action="/jsxsd/xk/LoginToXk">
  <label>学号 <input name="userAccount" type="text"></label>
  <label>密码 <input name="userPassword" type="password"></label>
  <button type="submit">登录</button>
</form>
</body></html>`;

const qzSchedulePage = `<!doctype html><html><head><meta charset="utf-8"><title>学生课表</title></head><body>
<div class="tools">
  <select name="xnxq01id"><option value="2025-2026-2">2025-2026学年第二学期</option><option value="2026-2027-1" selected>2026-2027学年第一学期</option></select>
</div>
${fixture.replace(/^[\s\S]*<body>|<\/body>[\s\S]*$/gi, '')}
</body></html>`;

function parseCookies(req) {
  const map = new Map();
  for (const pair of (req.headers.cookie || '').split(';')) {
    const [key, value] = pair.trim().split('=');
    if (key) map.set(key, value);
  }
  return map;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const cookies = parseCookies(req);
  const session = sessions.get(cookies.get('JSESSIONID'));
  const authed = session?.authed;

  if (url.pathname === '/jwglxt/xtgl/login_slogin.html') {
    if (req.method === 'GET') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'set-cookie': `JSESSIONID=${cookies.get('JSESSIONID') || 'sess-login'}; Path=/; HttpOnly` });
      res.end(loginPage());
      return;
    }
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      const params = new URLSearchParams(body);
      if (params.get('yhm') === '2026001' && params.get('mm') === 'wakeclass') {
        const id = `sess-${Date.now()}`;
        sessions.set(id, { authed: true, user: params.get('yhm') });
        res.writeHead(302, {
          location: '/jwglxt/xtgl/index_initMenu.html',
          'set-cookie': `JSESSIONID=${id}; Path=/; HttpOnly`,
        });
        res.end();
      } else {
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
        res.end(loginPage('用户名或密码不正确'));
      }
    });
    return;
  }

  if (url.pathname === '/jwglxt/xtgl/index_initMenu.html') {
    res.writeHead(authed ? 200 : 302, authed ? { 'content-type': 'text/html; charset=utf-8' } : { location: '/jwglxt/xtgl/login_slogin.html' });
    res.end(authed ? dashboard : '');
    return;
  }

  if (url.pathname === '/jwglxt/kbcx/xskbcx') {
    if (!authed) {
      res.writeHead(302, { location: '/jwglxt/xtgl/login_slogin.html' });
      res.end();
      return;
    }
    if (req.method === 'GET') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(schedulePage);
      return;
    }
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(schedulePage);
    });
    return;
  }

  if (url.pathname === '/jsxsd/') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(qzLoginPage());
    return;
  }

  if (url.pathname === '/jsxsd/xk/LoginToXk') {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      const params = new URLSearchParams(body);
      if (params.get('userAccount') === '2026002' && params.get('userPassword') === 'qzpass') {
        const id = `qz-${Date.now()}`;
        sessions.set(id, { authed: true, user: params.get('userAccount') });
        res.writeHead(302, {
          location: '/jsxsd/framework/xsMain.jsp',
          'set-cookie': `JSESSIONID=${id}; Path=/; HttpOnly`,
        });
        res.end();
      } else {
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
        res.end(qzLoginPage('用户名或密码错误'));
      }
    });
    return;
  }

  if (url.pathname === '/jsxsd/framework/xsMain.jsp') {
    res.writeHead(authed ? 200 : 302, authed ? { 'content-type': 'text/html; charset=utf-8' } : { location: '/jsxsd/' });
    res.end(authed ? '<html><body><a href="/jsxsd/xskb/xskb_list.do">我的课表</a></body></html>' : '');
    return;
  }

  if (url.pathname === '/jsxsd/xskb/xskb_list.do') {
    if (!authed) {
      res.writeHead(302, { location: '/jsxsd/' });
      res.end();
      return;
    }
    if (req.method === 'GET') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(qzSchedulePage);
      return;
    }
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(qzSchedulePage);
    });
    return;
  }

  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('Not found');
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Mock JWXT on http://127.0.0.1:${PORT}`);
});
