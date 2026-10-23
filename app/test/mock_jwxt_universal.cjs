#!/usr/bin/env node
/*
 * 本地模拟两套教务系统（用于集成测试，不依赖外网）：
 *
 * 1) 正方（jwglxt）   http://127.0.0.1:8791/zf/...
 *    - GET  /jwglxt/xtgl/login_slogin.html        登录页（含 csrftoken）
 *    - GET  /jwglxt/xtgl/login_getPublicKey.html  RSA 公钥（modulus/exponent）
 *    - POST /jwglxt/xtgl/login_slogin.html        密码用 RSA 加密提交
 *    - GET  /jwglxt/kbcx/xskbcx_cxXsKb.html       课表页（学年/学期下拉）
 *    - POST /jwglxt/kbcx/xskbcx_cxXsKb.html       课表 JSON（kbList）
 *    账号 2026005 / zfpass
 *
 * 2) 通用教务          http://127.0.0.1:8791/gen/...
 *    - GET  /gen/login.jsp      表单登录（xh / pwd + hidden token，无验证码）
 *    - POST /gen/doLogin        校验账号密码 → 302 到首页
 *    - GET  /gen/home.jsp       页面上有「我的课表」链接
 *    - GET  /gen/kb.jsp         课表 HTML 表格
 *    账号 2026004 / genpass
 */
const http = require('node:http');
const crypto = require('node:crypto');
const { URL } = require('node:url');

const PORT = Number(process.env.PORT || 8791);

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 1024,
});
const jwk = publicKey.export({ format: 'jwk' });
const modulusB64 = Buffer.from(jwk.n, 'base64url').toString('base64');
const exponentB64 = Buffer.from(jwk.e, 'base64url').toString('base64');

const ZF_USER = '2026005';
const ZF_PASS = 'zfpass';
const GEN_USER = '2026004';
const GEN_PASS = 'genpass';

const sessions = new Set();

function readBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => resolve(body));
  });
}

function parseForm(text) {
  const out = {};
  for (const [k, v] of new URLSearchParams(text)) out[k] = v;
  return out;
}

function cookies(req) {
  return (req.headers.cookie || '')
    .split(';')
    .map((p) => p.trim())
    .filter(Boolean);
}

function hasSession(req) {
  const list = cookies(req);
  for (const item of list) {
    const [k, v] = item.split('=');
    if (k === 'ZFSESSION' && sessions.has(v)) return true;
    if (k === 'GENSESSION' && sessions.has(v)) return true;
  }
  return false;
}

const zfLoginPage = (csrf) => `<!doctype html>
<html><head><meta charset="utf-8"><title>统一身份认证</title></head>
<body>
<h2>正方教务管理系统</h2>
<form id="loginForm" action="/jwglxt/xtgl/login_slogin.html" method="post">
  <input type="hidden" name="csrftoken" id="csrftoken" value="${csrf}">
  <input type="hidden" name="language" value="zh_CN">
  <label>用户名<input type="text" id="yhm" name="yhm"></label>
  <label>密码<input type="password" id="mm" name="mm"></label>
  <button type="submit">登录</button>
</form>
<script>var publicKey = 1;</script>
</body></html>`;

const zfSchedulePage = `<!doctype html>
<html><head><meta charset="utf-8"><title>课表查询</title></head>
<body>
<h2>学生课表</h2>
<select id="xnm" name="xnm">
  <option value="2025">2025-2026</option>
  <option value="2026" selected>2026-2027</option>
</select>
<select id="xqm" name="xqm">
  <option value="3" selected>1</option>
  <option value="12">2</option>
</select>
</body></html>`;

const genHome = `<!doctype html>
<html><head><meta charset="utf-8"><title>学生首页</title></head>
<body>
<h3>欢迎，2026004</h3>
<ul>
  <li><a href="/gen/kb.jsp">我的课表</a></li>
  <li><a href="/gen/score.jsp">成绩查询</a></li>
</ul>
</body></html>`;

const genKb = `<!doctype html>
<html><head><meta charset="utf-8"><title>我的课表</title></head>
<body>
<table border="1">
  <tr><td>节次</td><td>星期一</td><td>星期二</td><td>星期三</td><td>星期四</td><td>星期五</td></tr>
  <tr>
    <td>第1-2节</td>
    <td>高等数学A<br>张明远<br>1-16周<br>教一101</td>
    <td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td>
  </tr>
  <tr>
    <td>第3-4节</td>
    <td>&nbsp;</td><td>&nbsp;</td>
    <td>大学英语<br>李华<br>1-8周,10-16周<br>外语楼203</td>
    <td>&nbsp;</td><td>&nbsp;</td>
  </tr>
  <tr><td>第5-6节</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
  <tr><td>第7-8节</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table>
</body></html>`;

const genLoginPage = `<!doctype html>
<html><head><meta charset="utf-8"><title>教务系统登录</title></head>
<body>
<form action="/gen/doLogin" method="post">
  <input type="hidden" name="token" value="abc123">
  <input type="text" name="xh" placeholder="学号">
  <input type="password" name="pwd">
  <button type="submit">登录</button>
</form>
</body></html>`;

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const path = url.pathname;
  const body = req.method === 'POST' ? await readBody(req) : '';

  // ---------- 正方 ----------
  if (path === '/jwglxt/xtgl/login_slogin.html' && req.method === 'GET') {
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Set-Cookie': 'csrftoken=zf-csrf-001; Path=/',
    });
    res.end(zfLoginPage('zf-csrf-001'));
    return;
  }
  if (path === '/jwglxt/xtgl/login_getPublicKey.html') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ modulus: modulusB64, exponent: exponentB64 }));
    return;
  }
  if (path === '/jwglxt/xtgl/login_slogin.html' && req.method === 'POST') {
    const form = parseForm(body);
    let plain = '';
    try {
      plain = crypto
        .privateDecrypt(
          { key: privateKey, padding: crypto.constants.RSA_PKCS1_PADDING },
          Buffer.from(form.mm || '', 'hex'),
        )
        .toString('utf8');
    } catch (e) {
      plain = '';
    }
    const ok = form.yhm === ZF_USER && plain === ZF_PASS;
    if (!ok) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end('<html><body>用户名或密码不正确</body></html>');
      return;
    }
    const sid = crypto.randomUUID();
    sessions.add(sid);
    res.writeHead(302, {
      Location: '/jwglxt/xtgl/index_initMenu.html',
      'Set-Cookie': `ZFSESSION=${sid}; Path=/`,
    });
    res.end();
    return;
  }
  if (path === '/jwglxt/xtgl/index_initMenu.html') {
    if (!hasSession(req)) {
      res.writeHead(302, { Location: '/jwglxt/xtgl/login_slogin.html' });
      res.end();
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end('<html><body>正方首页</body></html>');
    return;
  }
  if (path === '/jwglxt/kbcx/xskbcx_cxXsKb.html') {
    if (!hasSession(req)) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end('<html><body><input type="password" name="mm"></body></html>');
      return;
    }
    if (req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(zfSchedulePage);
      return;
    }
    const form = parseForm(body);
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(
      JSON.stringify({
        xnm: form.xnm,
        xqm: form.xqm,
        kbList: [
          {
            kcmc: '高等数学A',
            xm: '张明远',
            cdmc: '教一101',
            xqj: '1',
            jcs: '1-2',
            zcd: '1-16周',
          },
          {
            kcmc: '大学英语',
            xm: '李华',
            cdmc: '外语楼203',
            xqj: '3',
            jcs: '3-4',
            zcd: '1-8周,10-16周',
          },
        ],
      }),
    );
    return;
  }

  // ---------- 通用 ----------
  if (path === '/gen/login.jsp') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(genLoginPage);
    return;
  }
  if (path === '/gen/doLogin' && req.method === 'POST') {
    const form = parseForm(body);
    if (form.xh === GEN_USER && form.pwd === GEN_PASS) {
      const sid = crypto.randomUUID();
      sessions.add(sid);
      res.writeHead(302, {
        Location: '/gen/home.jsp',
        'Set-Cookie': `GENSESSION=${sid}; Path=/`,
      });
      res.end();
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end('<html><body>用户名或密码错误</body></html>');
    return;
  }
  if (path === '/gen/home.jsp') {
    if (!hasSession(req)) {
      res.writeHead(302, { Location: '/gen/login.jsp' });
      res.end();
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(genHome);
    return;
  }
  if (path === '/gen/kb.jsp') {
    if (!hasSession(req)) {
      res.writeHead(302, { Location: '/gen/login.jsp' });
      res.end();
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(genKb);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('not found');
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`mock 教务系统已启动：http://127.0.0.1:${PORT}`);
  console.log(`  正方：/jwglxt/...  账号 ${ZF_USER}/${ZF_PASS}`);
  console.log(`  通用：/gen/login.jsp 账号 ${GEN_USER}/${GEN_PASS}`);
});
