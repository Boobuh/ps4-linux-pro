// Minimal Language for PS4LINUX_MINIMAL_MENU — no nlohmann (keeps eboot under GoldHEN OneFamily ceiling).
// License: GPL-3.0

#include "Language.h"

#include <orbis/SystemService.h>

#include <cstdio>
#include <string>
#include <vector>

#include "libLog.h"

Language::Language() {
  m_Code = GetCode();
  m_Name = GetName();
  m_TypefacePaths = GetTypefacePaths();
}

Language::~Language() {
  m_TypefacePaths.clear();
  m_Name.clear();
  m_Code = -1;
}

std::string Language::Get(const std::string &p_Key) {
  if (p_Key == "errorFatal") {
    return "Fatal error";
  }
  if (p_Key == "errorCloseApplication") {
    return "Close with PS button.";
  }
  if (p_Key == "unknownKey") {
    return "[UNTRANSLATED TEXT]";
  }
  return "[UNTRANSLATED TEXT]";
}

int32_t Language::GetCode() {
  int32_t s_Code;
  if (sceSystemServiceParamGetInt(ORBIS_SYSTEM_SERVICE_PARAM_ID_LANG, &s_Code) != 0) {
    logKernel(LL_Debug, "%s", "Unable to query language code");
    return 0x1;
  }
  return s_Code;
}

std::string Language::GetName() {
  switch (m_Code) {
  case 0:
    return "Japanese";
  case 1:
    return "English (United States)";
  default:
    return "English (United States)";
  }
}

std::vector<std::string> Language::GetTypefacePaths() {
  std::vector<std::string> paths;
  switch (m_Code) {
  case 0:
    paths.push_back("/app0/assets/fonts/NotoSansJP-Regular.ttf");
    break;
  case 9:
    paths.push_back("/app0/assets/fonts/NotoSansKR-Regular.ttf");
    break;
  case 10:
    paths.push_back("/app0/assets/fonts/NotoSansTC-Regular.ttf");
    break;
  case 11:
    paths.push_back("/app0/assets/fonts/NotoSansSC-Regular.ttf");
    break;
  case 21:
    paths.push_back("/app0/assets/fonts/NotoSansArabic-Regular.ttf");
    break;
  case 27:
    paths.push_back("/app0/assets/fonts/NotoSansThai-Regular.ttf");
    break;
  default:
    break;
  }
  paths.push_back("/app0/assets/fonts/NotoSans-Regular.ttf");
  return paths;
}
