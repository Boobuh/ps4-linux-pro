// This is an open source non-commercial project. Dear PVS-Studio, please check it.
// PVS-Studio Static Code Analyzer for C, C++, C#, and Java: http://www.viva64.com

// License: GPL-3.0

#ifndef LANGUAGE_H
#define LANGUAGE_H

#include <cstdint>
#include <string>
#include <vector>

#if !defined(PS4LINUX_MINIMAL_MENU)
#include <nlohmann_json.hpp>
#endif

class Language {
public:
  Language();
  ~Language();

  std::string Get(const std::string &p_Key);

  int32_t GetCode();
  std::string GetName();
  std::vector<std::string> GetTypefacePaths();
#if !defined(PS4LINUX_MINIMAL_MENU)
  nlohmann::json GetData();

  nlohmann::json Fallback();
#endif

private:
#if !defined(PS4LINUX_MINIMAL_MENU)
  nlohmann::json m_Data;
#endif
  int32_t m_Code;
  std::string m_Name;
  std::vector<std::string> m_TypefacePaths;
};

#endif
