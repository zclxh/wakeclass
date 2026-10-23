/// 电脑浏览器里「一键取课表」的书签脚本（bookmarklet）。
///
/// 背景：正方（jwglxt）的课表格子是浏览器里用 JS 画出来的，
/// 右键「查看网页源代码」只能拿到空壳，拿不到课程；
/// 强智 / 青果 / URP 等多数是服务器直接渲染，源代码里就有表格。
///
/// 用法：电脑浏览器新建一个书签 →「网址」粘贴下面整段 → 打开课表页 → 点这个书签。
/// 脚本会把课表数据复制到剪贴板，再发到手机（微信文件传输助手）→ 粘贴导入。
class PcCaptureScripts {
  PcCaptureScripts._();

  /// 正方（jwglxt）：直接调课表接口拿 `kbList` JSON —— 最准，含单双周、教室。
  static const String zfsoft = r'javascript:(async()=>{const cp=t=>new Promise((ok,no)=>{try{if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(t).then(ok,no);return}const a=document.createElement("textarea");a.value=t;a.style.position="fixed";a.style.opacity="0";document.body.appendChild(a);a.select();const r=document.execCommand("copy");a.remove();r?ok():no(new Error("浏览器拒绝复制"))}catch(e){no(e)}});try{const base=location.pathname.split("/kbcx/")[0];const q=new URLSearchParams();q.set("xnm",(document.querySelector("#xnm")||{}).value||"");q.set("xqm",(document.querySelector("#xqm")||{}).value||"");q.set("kzlx","ck");const r=await fetch(base+"/kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded;charset=UTF-8"},body:q.toString()});const t=await r.text();if(!t||t.length<20)throw new Error("接口没有返回内容");await cp(t);alert("已复制 "+t.length+" 个字符。\n发到手机后用「粘贴导入」")}catch(e){alert("取数据失败："+e+"\n备选：F12 → Network → xskbcx_cxXsKb.html → 右键 Copy response")}})()';

  /// 任意系统：把页面上已经渲染好的课表表格 HTML 复制出来。
  static const String table = r'javascript:(()=>{const ts=[...document.querySelectorAll("table")];let best=null,score=0;for(const t of ts){const n=(t.textContent.match(/星期[一二三四五六日天]/g)||[]).length;if(n>score){score=n;best=t}}if(!best){alert("没找到课表表格：请先打开课表页面（能看到课程格子）");return}const h=best.outerHTML;const a=document.createElement("textarea");a.value=h;a.style.position="fixed";a.style.opacity="0";document.body.appendChild(a);a.select();const ok=document.execCommand("copy");a.remove();alert(ok?("已复制表格 "+h.length+" 个字符，发到手机后粘贴导入"):"复制失败：请改用 F12 复制")})()';
}
