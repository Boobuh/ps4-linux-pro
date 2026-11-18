#include "Ps4NetworkInherit.h"

#include <arpa/inet.h>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <ifaddrs.h>
#include <net/if.h>
#include <string>

#include "AppFileLog.h"
#include "Utility.h"

namespace {

static bool isWifiIface(const char *name) {
  if (name == nullptr) {
    return false;
  }
  if (std::strncmp(name, "wlan", 4) == 0) {
    return true;
  }
  if (std::strncmp(name, "wl", 2) == 0) {
    return true;
  }
  return std::strstr(name, "wlan") != nullptr;
}

static bool maskToDotted(const struct sockaddr_in *mask, char *out, size_t outLen) {
  if (mask == nullptr || out == nullptr || outLen < INET_ADDRSTRLEN) {
    return false;
  }
  return inet_ntop(AF_INET, &mask->sin_addr, out, outLen) != nullptr;
}

static bool parseDefaultGw(char *gwOut, size_t gwLen) {
  FILE *pipe = popen("netstat -rn 2>/dev/null", "r");
  if (pipe == nullptr) {
    return false;
  }
  char line[256];
  bool got = false;
  while (std::fgets(line, sizeof(line), pipe) != nullptr) {
    if (std::strncmp(line, "default", 7) != 0) {
      continue;
    }
    char dest[64];
    char gw[64];
    if (std::sscanf(line, "%63s %63s", dest, gw) >= 2 && std::strcmp(dest, "default") == 0) {
      std::strncpy(gwOut, gw, gwLen - 1);
      gwOut[gwLen - 1] = '\0';
      got = gwOut[0] != '\0';
      break;
    }
  }
  pclose(pipe);
  return got;
}

} // namespace

bool WritePs4NetworkInheritConf() {
  struct ifaddrs *ifap = nullptr;
  if (getifaddrs(&ifap) != 0) {
    APP_LOG_ERRNO("WritePs4NetworkInherit getifaddrs", errno);
    return false;
  }

  std::string iface;
  std::string addr;
  std::string mask = "255.255.255.0";
  int wifi = 0;

  for (struct ifaddrs *ifa = ifap; ifa != nullptr; ifa = ifa->ifa_next) {
    if (ifa->ifa_addr == nullptr || ifa->ifa_addr->sa_family != AF_INET) {
      continue;
    }
    if ((ifa->ifa_flags & IFF_UP) == 0 || (ifa->ifa_flags & IFF_LOOPBACK) != 0) {
      continue;
    }
    const auto *sin = reinterpret_cast<const struct sockaddr_in *>(ifa->ifa_addr);
    if (sin->sin_addr.s_addr == INADDR_ANY || sin->sin_addr.s_addr == INADDR_NONE) {
      continue;
    }
    char host[INET_ADDRSTRLEN];
    if (inet_ntop(AF_INET, &sin->sin_addr, host, sizeof(host)) == nullptr) {
      continue;
    }
  if (std::strcmp(host, "0.0.0.0") == 0 || std::strcmp(host, "127.0.0.1") == 0) {
      continue;
    }
    iface = ifa->ifa_name;
    addr = host;
    wifi = isWifiIface(ifa->ifa_name) ? 1 : 0;
    if (ifa->ifa_netmask != nullptr && ifa->ifa_netmask->sa_family == AF_INET) {
      char mbuf[INET_ADDRSTRLEN];
      const auto *msin = reinterpret_cast<const struct sockaddr_in *>(ifa->ifa_netmask);
      if (maskToDotted(msin, mbuf, sizeof(mbuf))) {
        mask = mbuf;
      }
    }
    break;
  }
  freeifaddrs(ifap);

  if (iface.empty() || addr.empty()) {
    APP_LOG_WARN("WritePs4NetworkInherit: no active IPv4 interface");
    return false;
  }

  char gw[64];
  gw[0] = '\0';
  (void)parseDefaultGw(gw, sizeof(gw));

  std::string body;
  body += "# PS4 Linux — Orbis network snapshot for install netdebug\n";
  body += "PS4_NET_IFACE=" + iface + "\n";
  body += "PS4_NET_WIFI=" + std::to_string(wifi) + "\n";
  body += "PS4_NET_ADDR=" + addr + "\n";
  body += "PS4_NET_MASK=" + mask + "\n";
  if (gw[0] != '\0') {
    body += std::string("PS4_NET_GW=") + gw + "\n";
  }
  body += "PS4_NET_INHERITED=1\n";

  bool ok = Utility::WriteTextFile("/data/linux/boot/ps4-net-inherit.conf", body);
  if (!Utility::WriteTextFile("/user/system/boot/ps4-net-inherit.conf", body)) {
    APP_LOG_WARN("WritePs4NetworkInherit: /user/system/boot write failed (initramfs may miss inherit)");
  } else {
    ok = true;
  }

  APP_LOG_INFO("WritePs4NetworkInherit OK iface=%s addr=%s wifi=%d gw=%s", iface.c_str(), addr.c_str(), wifi,
               gw[0] ? gw : "(none)");
  return ok;
}