/// 教务系统地址相关的工具：WebVPN 前缀、内网判断、站点根地址。
///
/// 很多学校只允许校园网 / VPN 访问教务，常见两种形态：
/// 1. **系统级 VPN**：手机先连学校 VPN（或连校园 Wi-Fi），App 直接访问内网地址；
/// 2. **WebVPN（网页版 VPN）**：地址里带一段「/https/一长串」或「/webvpn/一长串」，
///    后面的路径和真实系统一样。只要把这种地址原样粘贴进来，这里会把前缀保留下来，
///    后续的课表接口请求也会带着同样的前缀。
library;

/// 已知的教务系统根路径标记（按优先级）。
const _rootMarkers = ['/jwglxt', '/jsxsd', '/eams', '/xtgl'];

/// 是否像校园内网地址（需要先连 VPN / 校园网）。
bool looksIntranet(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  if (host == 'localhost' || host.endsWith('.local')) return true;
  if (host.startsWith('10.')) return true;
  if (host.startsWith('127.') || host.startsWith('192.168.')) return true;
  final match = RegExp(r'^172\.(\d{1,2})\.').firstMatch(host);
  if (match != null) {
    final second = int.tryParse(match.group(1)!) ?? 0;
    if (second >= 16 && second <= 31) return true;
  }
  // 校内常见域名：jwxt.xxx.edu.cn 之外的纯内网域名不好判断，这里只覆盖明显特征。
  if (host.endsWith('.edu.cn') &&
      RegExp(r'^(jw|jwxt|jwc|jwgl|my|portal)\.').hasMatch(host)) {
    return false;
  }
  return false;
}

/// 是否是 WebVPN 地址（地址里带 /https/<token> 或 /webvpn/<token>）。
bool isWebVpn(String url) =>
    RegExp(r'/(https?|webvpn)/[^/]{8,}/', caseSensitive: false)
        .hasMatch(url);

/// 内网 / VPN 相关的提示文案（不是内网或 WebVPN 时返回 null）。
String? networkHint(String url) {
  if (isWebVpn(url)) {
    return '这是 WebVPN 地址：已保留 WebVPN 前缀，请保持 VPN 登录状态再导入。';
  }
  if (looksIntranet(url)) {
    return '这是内网地址：请先连上学校 VPN 或校园网，再点登录；'
        '也可以改用 WebVPN 地址（地址里带 /https/ 一长串）。';
  }
  return null;
}

/// WebVPN 前缀：登录页路径里「/jwglxt」之前的部分（没有则为空串）。
///
/// 例：`/https/77726476706e69737468656265737421.../jwglxt/xtgl/login_slogin.html`
/// → `/https/77726476706e69737468656265737421...`
String webVpnPrefix(String path) {
  final lower = path.toLowerCase();
  for (final marker in _rootMarkers) {
    final index = lower.indexOf(marker);
    if (index >= 0) {
      return index == 0 ? '' : path.substring(0, index);
    }
  }
  final match =
      RegExp(r'^(/.*?/(?:https?|webvpn)/[^/]+)', caseSensitive: false)
          .firstMatch(path);
  return match?.group(1) ?? '';
}

/// 教务系统根地址（保留 WebVPN 前缀）。
///
/// - 直接地址：`https://jw.x.edu.cn/jwglxt/xtgl/login_slogin.html` → `https://jw.x.edu.cn/jwglxt/`
/// - WebVPN：`https://webvpn.x.edu.cn/https/<token>/jwglxt/xtgl/login...`
///   → `https://webvpn.x.edu.cn/https/<token>/jwglxt/`
String siteRoot(String url, {String fallbackMarker = '/jwglxt'}) {
  final uri = Uri.parse(url.trim());
  final path = uri.path;
  final lower = path.toLowerCase();
  final origin = '${uri.scheme}://${uri.authority}';
  for (final marker in _rootMarkers) {
    final index = lower.indexOf(marker);
    if (index < 0) continue;
    // `/xtgl/...` 单独出现时，根目录是它前面的部分（正方实际根是 /jwglxt/）。
    if (marker == '/xtgl') {
      return '$origin${path.substring(0, index)}/';
    }
    return '$origin${path.substring(0, index)}$marker/';
  }
  return '$origin${webVpnPrefix(path)}$fallbackMarker/';
}
