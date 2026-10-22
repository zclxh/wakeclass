// 本地模拟「CAS 统一认证 + URP 教务系统」服务器（端口 8790）
// 用于 CasUrpClient 的端到端集成测试。
//
// 测试账号：2026003 / caspass；captchauser 触发验证码流程（验证码固定 1234）。
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = Number(process.env.MOCK_CAS_PORT) || 8790;
const FIXTURE = fs.readFileSync(
  path.join(__dirname, 'fixtures', 'zf.html'),
  'utf8',
);
const SALT = 'VambL0PEjllx5yfC';

// 与服务端一致地校验密码（IV 未知 → 首块损坏，密码从第 65 字节起）。
function decryptPassword(encBase64) {
  const key = Buffer.from(SALT, 'utf8');
  const iv = Buffer.alloc(16, 0);
  const decipher = crypto.createDecipheriv('aes-128-cbc', key, iv);
  decipher.setAutoPadding(true);
  const out = Buffer.concat([
    decipher.update(Buffer.from(encBase64, 'base64')),
    decipher.final(),
  ]);
  return out.toString('utf8').slice(64);
}

const loginPage = (service) => `<!doctype html><html><head><meta charset="utf-8"><title>统一身份认证平台</title></head>
<body>
<form class="loginFromClass" method="post" id="pwdFromId" action="/authserver/login">
  <div class="form">
    <div><input id="username" name="username" type="text" placeholder="请输入学号/工号"></div>
    <div><input id="passwordText" name="passwordText" type="password" placeholder="请输入密码"><input id="saltPassword" name="password" type="hidden"></div>
    <div class="captcha item hide" id="captchaDiv">
      <img id="captchaImg" alt="验证码错误" height="30px">
      <input type="text" id="captcha" name="captcha" placeholder="请输入验证码" maxlength="10" value="">
    </div>
  </div>
  <div id="formErrorTip"><span id="showErrorTip" class="form-error"></span></div>
  <input type="hidden" id="_eventId" name="_eventId" value="submit">
  <input type="hidden" id="cllt" name="cllt" value="userNameLogin">
  <input type="hidden" id="dllt" name="dllt" value="generalLogin">
  <input type="hidden" name="lt" id="lt" value="">
  <input type="hidden" id="pwdEncryptSalt" value="${SALT}">
  <input type="hidden" id="execution" name="execution" value="mock-execution-abc123">
</form>
</body></html>`;

const homePage = `<!doctype html><html><head><meta charset="utf-8"><title>教务系统</title></head>
<body>
<div class="menu">
  <a href="/eams/courseTableForStd!courseTable.action?projectId=1">我的课表</a>
  <a href="/eams/homeExt.action">首页</a>
</div>
</body></html>`;

// 1x1 PNG（验证码图片占位）。
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const html = (body) => {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(body);
  };

  if (url.pathname === '/authserver/login' && req.method === 'GET') {
    html(loginPage(url.searchParams.get('service') || ''));
    return;
  }

  if (url.pathname === '/authserver/getCaptcha.htl') {
    res.writeHead(200, { 'content-type': 'image/png' });
    res.end(PNG);
    return;
  }

  if (url.pathname === '/authserver/login' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const params = new URLSearchParams(body);
      const username = params.get('username') || '';
      const encrypted = params.get('password') || '';
      const captcha = params.get('captcha') || '';
      const service = url.searchParams.get('service') || '/eams/homeExt.action';

      if (username === 'captchauser' && !captcha) {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ code: 'captchaError', message: '需要验证码' }));
        return;
      }
      let password = '';
      try {
        password = decryptPassword(encrypted);
      } catch (_) {
        password = '';
      }
      if (username === '2026003' && password === 'caspass') {
        res.writeHead(302, {
          location: `${service}?ticket=ST-mock-ticket-123`,
        });
        res.end();
        return;
      }
      if (username === 'captchauser' && captcha === '1234') {
        res.writeHead(302, {
          location: `${service}?ticket=ST-mock-ticket-456`,
        });
        res.end();
        return;
      }
      html(`<div id="showErrorTip" class="form-error">用户名或密码错误</div>`);
    });
    return;
  }

  if (url.pathname === '/eams/homeExt.action') {
    res.writeHead(200, {
      'content-type': 'text/html; charset=utf-8',
      'set-cookie': 'JSESSIONID=mock-eams-session; Path=/; HttpOnly',
    });
    res.end(homePage);
    return;
  }

  if (url.pathname === '/eams/courseTableForStd!courseTable.action') {
    html(FIXTURE);
    return;
  }

  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('Not found');
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Mock CAS+URP on http://127.0.0.1:${PORT}`);
});
