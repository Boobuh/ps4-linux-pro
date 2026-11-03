#ifndef APP_FILE_LOG_H
#define APP_FILE_LOG_H

class AppFileLog {
public:
  static void InitSession();
  static void Info(const char *p_Format, ...);
  static void Warn(const char *p_File, int p_Line, const char *p_Format, ...);
  static void Error(const char *p_File, int p_Line, const char *p_Format, ...);
  static void ErrorErrno(const char *p_File, int p_Line, const char *p_Context, int p_Errno);
  static const char *LogPath();
};

#define APP_LOG_INFO(...) AppFileLog::Info(__VA_ARGS__)
#define APP_LOG_WARN(...) AppFileLog::Warn(__FILE__, __LINE__, __VA_ARGS__)
#define APP_LOG_ERROR(...) AppFileLog::Error(__FILE__, __LINE__, __VA_ARGS__)
#define APP_LOG_ERRNO(ctx, err) AppFileLog::ErrorErrno(__FILE__, __LINE__, (ctx), (err))

#endif
