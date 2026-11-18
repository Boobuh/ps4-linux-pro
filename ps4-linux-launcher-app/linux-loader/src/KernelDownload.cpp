#include "KernelDownload.h"

#include <cstdio>
#include <cstring>
#include <string>

#include <orbis/Http.h>
#include <orbis/Net.h>
#include <orbis/Ssl.h>
#include <orbis/_types/http.h>

#include "AppFileLog.h"

namespace {

struct HttpSession {
  int netPool = -1;
  int httpCtx = -1;
  int tmpl = -1;
  int conn = -1;
  int req = -1;
  bool netInit = false;
  bool sslInit = false;
};

void CloseRequest(HttpSession &s) {
  if (s.req >= 0) {
    sceHttpDeleteRequest(s.req);
    s.req = -1;
  }
  if (s.conn >= 0) {
    sceHttpDeleteConnection(s.conn);
    s.conn = -1;
  }
  if (s.tmpl >= 0) {
    sceHttpDeleteTemplate(s.tmpl);
    s.tmpl = -1;
  }
}

void ShutdownHttp(HttpSession &s) {
  CloseRequest(s);
  if (s.httpCtx >= 0) {
    sceHttpTerm(s.httpCtx);
    s.httpCtx = -1;
  }
  if (s.sslInit) {
    sceSslTerm();
    s.sslInit = false;
  }
  if (s.netPool >= 0) {
    sceNetPoolDestroy(s.netPool);
    s.netPool = -1;
  }
  if (s.netInit) {
    sceNetTerm();
    s.netInit = false;
  }
}

bool StartGet(HttpSession &s, const char *url, std::string &err) {
  s.netPool = sceNetPoolCreate("ps4linux_dl", 256 * 1024, 0);
  if (s.netPool < 0) {
    err = "sceNetPoolCreate failed";
    return false;
  }
  if (sceNetInit() < 0) {
    err = "sceNetInit failed — check PS4 network";
    return false;
  }
  s.netInit = true;

  const int sslCtx = sceSslInit(SSL_POOLSIZE);
  if (sslCtx < 0) {
    err = "sceSslInit failed";
    return false;
  }
  s.sslInit = true;

  s.httpCtx = sceHttpInit(s.netPool, sslCtx, LIBHTTP_POOLSIZE);
  if (s.httpCtx < 0) {
    err = "sceHttpInit failed";
    return false;
  }

  s.tmpl = sceHttpCreateTemplate(s.httpCtx, "PS4Linux-kernel-dl/1.0", ORBIS_HTTP_VERSION_1_1, 0);
  if (s.tmpl < 0) {
    err = "sceHttpCreateTemplate failed";
    return false;
  }

  s.conn = sceHttpCreateConnectionWithURL(s.tmpl, url, true);
  if (s.conn < 0) {
    err = "sceHttpCreateConnectionWithURL failed";
    return false;
  }

  s.req = sceHttpCreateRequest2(s.conn, "GET", "", 0);
  if (s.req < 0) {
    err = "sceHttpCreateRequest2 failed";
    return false;
  }

  sceHttpSetConnectTimeOut(s.req, 60 * 1000 * 1000);

  if (sceHttpSendRequest(s.req, nullptr, 0) < 0) {
    err = "sceHttpSendRequest failed";
    return false;
  }

  int status = 0;
  if (sceHttpGetStatusCode(s.req, &status) < 0 || status != 200) {
    char buf[96];
    std::snprintf(buf, sizeof(buf), "HTTP status %d (expected 200)", status);
    err = buf;
    return false;
  }
  return true;
}

} // namespace

namespace KernelDownload {

KernelDownloadResult DownloadEntry(const KernelCatalogEntry &entry) {
  KernelDownloadResult out;
  if (entry.url == nullptr || entry.destPath == nullptr) {
    out.error = "Invalid catalog entry";
    return out;
  }

  APP_LOG_INFO("KernelDownload: %s -> %s", entry.id, entry.destPath);

  const std::string partPath = std::string(entry.destPath) + ".part";

  HttpSession session;
  std::string err;
  if (!StartGet(session, entry.url, err)) {
    out.error = err;
    ShutdownHttp(session);
    return out;
  }

  FILE *f = std::fopen(partPath.c_str(), "wb");
  if (f == nullptr) {
    out.error = "Could not open temp file (need write under /data/linux/boot/)";
    ShutdownHttp(session);
    return out;
  }

  unsigned char buf[128 * 1024];
  int64_t total = 0;
  for (;;) {
    const int n = sceHttpReadData(session.req, buf, sizeof(buf));
    if (n == 0) {
      break;
    }
    if (n < 0) {
      out.error = "sceHttpReadData failed";
      std::fclose(f);
      std::remove(partPath.c_str());
      ShutdownHttp(session);
      return out;
    }
    if (std::fwrite(buf, 1, static_cast<size_t>(n), f) != static_cast<size_t>(n)) {
      out.error = "Disk write failed";
      std::fclose(f);
      std::remove(partPath.c_str());
      ShutdownHttp(session);
      return out;
    }
    total += n;
    if (entry.maxBytes > 0 && total > entry.maxBytes) {
      out.error = "Download larger than expected (abort)";
      std::fclose(f);
      std::remove(partPath.c_str());
      ShutdownHttp(session);
      return out;
    }
  }
  std::fclose(f);
  ShutdownHttp(session);

  if (entry.minBytes > 0 && total < entry.minBytes) {
    out.error = "Download too small — check network";
    std::remove(partPath.c_str());
    return out;
  }
  if (entry.expectedBytes > 0 && total != entry.expectedBytes) {
    char msg[128];
    std::snprintf(msg, sizeof(msg), "Size %lld B (expected %lld)", static_cast<long long>(total),
                  static_cast<long long>(entry.expectedBytes));
    APP_LOG_WARN("KernelDownload: %s — keeping file", msg);
  }

  std::remove(entry.destPath);
  if (std::rename(partPath.c_str(), entry.destPath) != 0) {
    out.error = "Could not install bzImage (rename failed)";
    return out;
  }

  const std::string metaPath = "/data/linux/boot/ps4-kernel-id.txt";
  FILE *meta = std::fopen(metaPath.c_str(), "w");
  if (meta != nullptr) {
    std::fprintf(meta, "%s\n", entry.id);
    std::fclose(meta);
  }

  out.ok = true;
  out.bytesWritten = total;
  APP_LOG_INFO("KernelDownload OK %lld bytes kernel=%s", static_cast<long long>(total), entry.id);
  return out;
}

} // namespace KernelDownload