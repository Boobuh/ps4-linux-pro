// License: GPL-3.0

#include "Controller.h"

#ifndef PS4LINUX_TV_REMOTE_INPUT
#define PS4LINUX_TV_REMOTE_INPUT 0
#endif

#if PS4LINUX_TV_REMOTE_INPUT
#include <orbis/Keyboard.h>
#endif
#include <orbis/Pad.h>
#include <orbis/SystemService.h>
#include <orbis/UserService.h>
#include <orbis/_types/errors.h>
#include <orbis/_types/sys_service.h>
#include <orbis/_types/user.h>

#include <cstring>

#include "AppFileLog.h"
#include "SystemServiceRuntime.h"
#include "libLog.h"

static constexpr uint8_t kStickLow = 0x40;
static constexpr uint8_t kStickHigh = 0xC0;

#if PS4LINUX_TV_REMOTE_INPUT
static constexpr uint16_t kHidUp = 82;
static constexpr uint16_t kHidDown = 81;
static constexpr uint16_t kHidLeft = 80;
static constexpr uint16_t kHidRight = 79;

static constexpr unsigned int kTvRemoteOkMask = PS4LINUX_TV_REMOTE_OK_MASK;
#endif

static bool isPadHandle(int handle) { return handle >= 0; }

#if PS4LINUX_TV_REMOTE_INPUT
static unsigned int mapTvRemoteButtons(unsigned int raw) {
  raw = ps4linuxNormalizePadButtons(raw);
  const unsigned int cleaned =
      raw & ~ORBIS_PAD_BUTTON_PLAYSTATION & ~PS4LINUX_TV_REMOTE_OPTIONS_KEY_MASK;
  unsigned int mapped = cleaned;
  if ((cleaned & kTvRemoteOkMask) != 0) {
    mapped |= ORBIS_PAD_BUTTON_CROSS;
  }
  return mapped;
}

#endif

#if PS4LINUX_TV_REMOTE_INPUT
static unsigned int keycodeToPadButton(uint16_t key) {
  switch (key) {
  case ORBIS_KEYBOARD_KEY_RETURN:
    return ORBIS_PAD_BUTTON_CROSS;
  case ORBIS_KEYBOARD_KEY_ESCAPE:
    return ORBIS_PAD_BUTTON_CIRCLE;
  case kHidUp:
  case ORBIS_KEYBOARD_KEY_HOME:
    return ORBIS_PAD_BUTTON_UP;
  case kHidDown:
  case ORBIS_KEYBOARD_KEY_END:
    return ORBIS_PAD_BUTTON_DOWN;
  case kHidLeft:
    return ORBIS_PAD_BUTTON_LEFT;
  case kHidRight:
    return ORBIS_PAD_BUTTON_RIGHT;
  case ORBIS_KEYBOARD_KEY_BACKSPACE:
    return ORBIS_PAD_BUTTON_SQUARE;
  default:
    if (key == 'r' || key == 'R') {
      return ORBIS_PAD_BUTTON_SQUARE;
    }
    return 0;
  }
}
#endif

Controller::Controller()
    : m_UserId(-1), m_PadId(-1), m_SystemStdPadId(-1), m_TvRemotePadId(-1),
      m_TvRemotePadOwned(false),
      m_KeyboardHandle(-1), m_LastStandardButtons(0), m_LastSystemStdButtons(0), m_LastTvRemoteButtons(0),
      m_ButtonsPressed(0), m_ButtonsReleased(0),
      m_CurrentButtons(0), m_ButtonsHold(0), m_EnterIsCross(true), m_MenuConfirmLatchFrames(0),
      m_TvRemoteDownHoldFrames(0), m_TvRemoteDownConfirmFired(false) {
  std::memset(m_KeyboardKeyDown, 0, sizeof(m_KeyboardKeyDown));
  std::memset(&m_PadData, 0, sizeof(m_PadData));

  EnsureUserServiceReady();

  int32_t enterAssign = ORBIS_SYSTEM_PARAM_ENTER_BUTTON_ASSIGN_CROSS;
  if (sceSystemServiceParamGetInt(ORBIS_SYSTEM_SERVICE_PARAM_ID_ENTER_BUTTON_ASSIGN, &enterAssign) == 0) {
    m_EnterIsCross = enterAssign == ORBIS_SYSTEM_PARAM_ENTER_BUTTON_ASSIGN_CROSS;
  }
  APP_LOG_INFO("Enter button assign: %s", m_EnterIsCross ? "Cross" : "Circle");

  if (scePadInit() != 0) {
    logKernel(LL_Debug, "%s", "Failed to initialize pad library!");
  } else {
    TryAttachInputDevices();
    (void)scePadSetProcessFocus();
  }

#if PS4LINUX_TV_REMOTE_INPUT
  if (sceKeyboardInit() == 0) {
    m_KeyboardHandle = sceKeyboardOpen(m_UserId, 0, 0, NULL);
    if (m_KeyboardHandle >= 0) {
      (void)sceKeyboardSetProcessFocus();
    }
  }
#endif

  APP_LOG_INFO("Input: ds4=%d systemStd=%d tvRemote=%d keyboard=%d user=%d tvInput=%d", m_PadId, m_SystemStdPadId,
               m_TvRemotePadId, m_KeyboardHandle, m_UserId, PS4LINUX_TV_REMOTE_INPUT);
}

Controller::~Controller() {
#if PS4LINUX_TV_REMOTE_INPUT
  if (m_KeyboardHandle >= 0) {
    sceKeyboardClose(m_KeyboardHandle);
  }
  if (m_TvRemotePadOwned && m_TvRemotePadId >= 0) {
    scePadClose(m_TvRemotePadId);
  }
  if (m_SystemStdPadId >= 0 && m_SystemStdPadId != m_PadId) {
    scePadClose(m_SystemStdPadId);
  }
#endif
  if (m_PadId >= 0) {
    scePadClose(m_PadId);
  }
}

bool Controller::HasAnyInputDevice() const {
#if PS4LINUX_TV_REMOTE_INPUT
  return m_PadId >= 0 || m_SystemStdPadId >= 0 || m_TvRemotePadId >= 0 || m_KeyboardHandle >= 0;
#else
  return m_PadId >= 0;
#endif
}

unsigned int Controller::AdjustFaceButtonFilter(unsigned int filter) const {
  if (!m_EnterIsCross && (filter & (ORBIS_PAD_BUTTON_CROSS | ORBIS_PAD_BUTTON_CIRCLE)) != 0) {
    filter ^= (ORBIS_PAD_BUTTON_CROSS | ORBIS_PAD_BUTTON_CIRCLE);
  }
  return filter;
}

unsigned int Controller::ButtonsWithStickAsDpad(const OrbisPadData &data) {
  unsigned int buttons = data.buttons;
  if (data.leftStick.y < kStickLow) {
    buttons |= ORBIS_PAD_BUTTON_UP;
  }
  if (data.leftStick.y > kStickHigh) {
    buttons |= ORBIS_PAD_BUTTON_DOWN;
  }
  if (data.leftStick.x < kStickLow) {
    buttons |= ORBIS_PAD_BUTTON_LEFT;
  }
  if (data.leftStick.x > kStickHigh) {
    buttons |= ORBIS_PAD_BUTTON_RIGHT;
  }
  return buttons;
}

void Controller::EnsureUserServiceReady() {
  OrbisUserServiceInitializeParams params {};
  params.priority = ORBIS_KERNEL_PRIO_FIFO_LOWEST;
  const int32_t initRc = sceUserServiceInitialize(&params);
  const uint32_t initErr = static_cast<uint32_t>(initRc);
  if (initErr != ORBIS_OK && initErr != ORBIS_USER_SERVICE_ERROR_ALREADY_INITIALIZED) {
    APP_LOG_WARN("UserServiceInitialize rc=0x%08x", initErr);
  }

  if (sceUserServiceGetInitialUser(&m_UserId) != ORBIS_OK || m_UserId < 0) {
    (void)sceUserServiceGetForegroundUser(&m_UserId);
  }
}

void Controller::TryAttachInputDevices() {
  if (m_UserId < 0) {
    return;
  }

  if (m_PadId < 0) {
    // Apollo / most homebrew: logged-in user, standard port (TV OK + DS4 on same handle).
    m_PadId = scePadOpen(m_UserId, ORBIS_PAD_PORT_TYPE_STANDARD, 0, NULL);
    if (m_PadId < 0) {
      m_PadId = scePadOpen(m_UserId, 0, 0, NULL);
    }
  }

#if PS4LINUX_TV_REMOTE_INPUT
  if (m_SystemStdPadId < 0) {
    for (int index = 0; index < 4 && m_SystemStdPadId < 0; index++) {
      int h = scePadOpen(ORBIS_USER_SERVICE_USER_ID_SYSTEM, ORBIS_PAD_PORT_TYPE_STANDARD, index, NULL);
      if (!isPadHandle(h)) {
        h = scePadGetHandle(ORBIS_USER_SERVICE_USER_ID_SYSTEM, ORBIS_PAD_PORT_TYPE_STANDARD, index);
      }
      if (!isPadHandle(h) && m_UserId >= 0) {
        h = scePadGetHandle(m_UserId, ORBIS_PAD_PORT_TYPE_STANDARD, index);
      }
      if (isPadHandle(h) && h != m_PadId) {
        m_SystemStdPadId = h;
        APP_LOG_INFO("System standard pad handle=%d index=%d (TV OK / CEC face buttons)", h, index);
      }
    }
  }

  if (m_TvRemotePadId < 0) {
    for (int index = 0; index < 4 && m_TvRemotePadId < 0; index++) {
      int tv = scePadOpen(ORBIS_USER_SERVICE_USER_ID_SYSTEM, ORBIS_PAD_PORT_TYPE_REMOTE_CONTROL, index, NULL);
      if (isPadHandle(tv)) {
        m_TvRemotePadId = tv;
        m_TvRemotePadOwned = true;
        APP_LOG_INFO("TV remote pad opened handle=%d index=%d (system/CEC dpad)", tv, index);
        break;
      }
      tv = scePadGetHandle(ORBIS_USER_SERVICE_USER_ID_SYSTEM, ORBIS_PAD_PORT_TYPE_REMOTE_CONTROL, index);
      if (isPadHandle(tv)) {
        m_TvRemotePadId = tv;
        APP_LOG_INFO("TV remote pad handle=%d index=%d (getHandle)", tv, index);
        break;
      }
    }
  }

  if (m_KeyboardHandle < 0 && sceKeyboardInit() == 0) {
    m_KeyboardHandle = sceKeyboardOpen(m_UserId, 0, 0, NULL);
    if (m_KeyboardHandle >= 0) {
      (void)sceKeyboardSetProcessFocus();
    }
  }
#else
  APP_LOG_INFO("Input: safe mode — user standard pad only (TV remote disabled for CE-34878 recovery)");
#endif
}

void Controller::PulseMenuConfirm() {
  m_MenuConfirmLatchFrames = 24;
  m_ButtonsPressed |= ORBIS_PAD_BUTTON_CROSS;
}

void Controller::ApplyPadSample(unsigned int actual, unsigned int &lastButtons, bool isTvRemote) {
#if !PS4LINUX_TV_REMOTE_INPUT
  (void)isTvRemote;
#endif
#if PS4LINUX_TV_REMOTE_INPUT
  const unsigned int rawActual = actual;
  const unsigned int normActual = ps4linuxNormalizePadButtons(actual);
  const unsigned int normLast = ps4linuxNormalizePadButtons(lastButtons);
  actual = normActual;
  const unsigned int logical = isTvRemote ? mapTvRemoteButtons(actual) : actual;
  const unsigned int lastLogical = isTvRemote ? mapTvRemoteButtons(normLast) : normLast;
#else
  const unsigned int normLast = lastButtons;
  const unsigned int logical = actual;
  const unsigned int lastLogical = normLast;
#endif

  m_CurrentButtons |= logical;
  m_ButtonsPressed |= logical & ~lastLogical;
  m_ButtonsReleased |= (~logical) & lastLogical;
  m_ButtonsHold |= logical & lastLogical;

#if PS4LINUX_TV_REMOTE_INPUT
  if (isTvRemote) {
    const unsigned int novel = actual & ~normLast;
    if (ps4linuxIsTvRemoteHomeRaw(rawActual) || (novel & ORBIS_PAD_BUTTON_PLAYSTATION) != 0) {
      SystemServiceNoteTvRemoteHomeIgnored();
      APP_LOG_INFO("TV remote Home raw=0x%08x (ignored for menu)", rawActual);
    }
    const unsigned int confirmNovel =
        novel & PS4LINUX_TV_REMOTE_OK_MASK & ~PS4LINUX_TV_REMOTE_HOME_MASK;
    if ((novel & PS4LINUX_TV_REMOTE_OPTIONS_KEY_MASK) != 0) {
      APP_LOG_INFO("TV remote Options (Triangle 0x1000) ignored raw=0x%08x", actual);
    }
    if (confirmNovel != 0) {
      PulseMenuConfirm();
      APP_LOG_INFO("TV remote OK/confirm raw=0x%08x novel=0x%08x", actual, confirmNovel);
    } else if ((logical & ORBIS_PAD_BUTTON_CROSS) != 0 && (lastLogical & ORBIS_PAD_BUTTON_CROSS) == 0) {
      PulseMenuConfirm();
      APP_LOG_INFO("TV remote OK/confirm raw=0x%08x", actual);
    }
  } else
#endif
  {
    const unsigned int face =
        actual & (ORBIS_PAD_BUTTON_CROSS | ORBIS_PAD_BUTTON_CIRCLE | ORBIS_PAD_BUTTON_L3 | ORBIS_PAD_BUTTON_R3);
    const unsigned int facePrev =
        normLast & (ORBIS_PAD_BUTTON_CROSS | ORBIS_PAD_BUTTON_CIRCLE | ORBIS_PAD_BUTTON_L3 | ORBIS_PAD_BUTTON_R3);
    if ((face & ~facePrev) != 0) {
      PulseMenuConfirm();
      APP_LOG_INFO("Main pad face press 0x%08x (enter=%s)", face & ~facePrev, m_EnterIsCross ? "Cross" : "Circle");
    }
  }

  lastButtons = actual;
}

void Controller::MergeStandardPadRead(int handle, unsigned int &lastButtons, OrbisPadData *outLatestState) {
  if (!isPadHandle(handle)) {
    return;
  }

  OrbisPadData batch[32];
  const int got = scePadRead(handle, batch, 32);
  if (got > 0) {
    for (int i = 0; i < got; i++) {
      const unsigned int actual = ButtonsWithStickAsDpad(batch[i]);
      if (batch[i].connected != 0 || actual != 0) {
        ApplyPadSample(actual, lastButtons, false);
      }
    }
  }

  OrbisPadData data {};
  if (scePadReadState(handle, &data) != 0) {
    return;
  }

  const unsigned int actual = ButtonsWithStickAsDpad(data);
  // TV OK often appears here (Apollo path) even when connected==0 and CEC dpad is on REMOTE handle.
  if (data.connected != 0 || actual != 0) {
    ApplyPadSample(actual, lastButtons, false);
  }
  if (outLatestState != nullptr) {
    *outLatestState = data;
  }
}

void Controller::MergePadRead(int handle, unsigned int &lastButtons, bool allowDisconnected, bool isTvRemote) {
  if (!isPadHandle(handle)) {
    return;
  }

  if (isTvRemote) {
    OrbisPadData batch[32];
    for (int drain = 0; drain < 8; drain++) {
      const int got = scePadRead(handle, batch, 32);
      if (got <= 0) {
        break;
      }
      for (int i = 0; i < got; i++) {
        if (batch[i].connected == 0 && !allowDisconnected) {
          continue;
        }
        ApplyPadSample(batch[i].buttons, lastButtons, true);
      }
    }

    OrbisPadData data {};
    scePadReadState(handle, &data);
    if (allowDisconnected || data.connected != 0) {
      ApplyPadSample(data.buttons, lastButtons, true);
    }
    return;
  }
}

unsigned int Controller::GetCurrentButtonsPressed() { return m_ButtonsPressed; }

void Controller::SetCurrentButtonsPressed(unsigned int p_Buttons) { m_ButtonsPressed = p_Buttons; }

unsigned int Controller::GetCurrentButtonsReleased() { return m_ButtonsReleased; }

void Controller::SetCurrentButtonsReleased(unsigned int p_Buttons) { m_ButtonsReleased = p_Buttons; }

bool Controller::GetButtonHold(unsigned int p_Filter) {
  return (m_ButtonsHold & AdjustFaceButtonFilter(p_Filter)) != 0;
}

bool Controller::GetButtonPressed(unsigned int p_Filter) {
  return (m_ButtonsPressed & AdjustFaceButtonFilter(p_Filter)) != 0;
}

bool Controller::GetButtonReleased(unsigned int p_Filter) {
  return (m_ButtonsReleased & AdjustFaceButtonFilter(p_Filter)) != 0;
}

bool Controller::GetMenuConfirmPressed() const {
  if (m_MenuConfirmLatchFrames > 0) {
    return true;
  }
  const unsigned int enterBtn =
      m_EnterIsCross ? ORBIS_PAD_BUTTON_CROSS : ORBIS_PAD_BUTTON_CIRCLE;
  if ((m_ButtonsPressed & enterBtn) != 0) {
    return true;
  }
  return (m_ButtonsPressed & (ORBIS_PAD_BUTTON_CROSS | ORBIS_PAD_BUTTON_CIRCLE)) != 0;
}

void Controller::ConsumeMenuConfirm() { m_MenuConfirmLatchFrames = 0; }

#if PS4LINUX_TV_REMOTE_INPUT
void Controller::ReadKeyboardIntoState() {
  if (m_KeyboardHandle < 0) {
    return;
  }

  OrbisKeyboardData kbd {};
  sceKeyboardReadState(m_KeyboardHandle, &kbd);

  bool downNow[128] {};
  for (int i = 0; i < kbd.nkeys && i < 32; i++) {
    const uint16_t key = kbd.keycodes[i];
    if (key < 128) {
      downNow[key] = true;
    }
    const unsigned int mapped = keycodeToPadButton(key);
    if (mapped != 0) {
      m_CurrentButtons |= mapped;
      m_ButtonsHold |= mapped;
    }
    if (mapped == ORBIS_PAD_BUTTON_CROSS && !m_KeyboardKeyDown[key] && key < 128) {
      APP_LOG_INFO("Keyboard confirm key=%u", static_cast<unsigned>(key));
    }
  }

  for (unsigned key = 0; key < 128; key++) {
    const unsigned int mapped = keycodeToPadButton(static_cast<uint16_t>(key));
    if (mapped == 0) {
      continue;
    }
    if (downNow[key] && !m_KeyboardKeyDown[key]) {
      m_ButtonsPressed |= mapped;
      if (mapped == ORBIS_PAD_BUTTON_CROSS) {
        PulseMenuConfirm();
      }
    }
    if (!downNow[key] && m_KeyboardKeyDown[key]) {
      m_ButtonsReleased |= mapped;
    }
  }
  std::memcpy(m_KeyboardKeyDown, downNow, sizeof(downNow));
}
#else
void Controller::ReadKeyboardIntoState() {}
#endif

#if PS4LINUX_TV_REMOTE_INPUT
void Controller::UpdateTvRemoteHoldConfirm() {
  if (m_TvRemotePadId < 0) {
    m_TvRemoteDownHoldFrames = 0;
    m_TvRemoteDownConfirmFired = false;
    return;
  }

  const unsigned int tvOnly = m_LastTvRemoteButtons & ~PS4LINUX_TV_REMOTE_HOME_MASK;
  const bool downHeld =
      (tvOnly & ORBIS_PAD_BUTTON_DOWN) != 0 && (tvOnly & ~ORBIS_PAD_BUTTON_DOWN) == 0;

  if (downHeld && !m_TvRemoteDownConfirmFired) {
    if (m_TvRemoteDownHoldFrames < 600) {
      m_TvRemoteDownHoldFrames++;
    }
    if (m_TvRemoteDownHoldFrames == 45) {
      PulseMenuConfirm();
      m_TvRemoteDownConfirmFired = true;
      APP_LOG_INFO("TV remote hold Down ~750ms = confirm (center OK not sent by TV)");
    }
  } else {
    m_TvRemoteDownHoldFrames = 0;
    if (!downHeld) {
      m_TvRemoteDownConfirmFired = false;
    }
  }
}
#else
void Controller::UpdateTvRemoteHoldConfirm() {
  (void)m_LastSystemStdButtons;
  (void)m_LastTvRemoteButtons;
  (void)m_TvRemoteDownHoldFrames;
  (void)m_TvRemoteDownConfirmFired;
  (void)m_KeyboardKeyDown;
  (void)m_TvRemotePadOwned;
}
#endif

void Controller::Update() {
  static unsigned int s_AttachCounter = 0;
  s_AttachCounter++;
  if (s_AttachCounter <= 3 || !HasAnyInputDevice() || (s_AttachCounter % 15) == 0) {
    TryAttachInputDevices();
    (void)scePadSetProcessFocus();
  }

  m_ButtonsPressed = 0;
  m_ButtonsReleased = 0;
  m_CurrentButtons = 0;
  m_ButtonsHold = 0;
  MergeStandardPadRead(m_PadId, m_LastStandardButtons, &m_PadData);
#if PS4LINUX_TV_REMOTE_INPUT
  if (m_SystemStdPadId >= 0 && m_SystemStdPadId != m_PadId) {
    MergeStandardPadRead(m_SystemStdPadId, m_LastSystemStdButtons, nullptr);
  }
  MergePadRead(m_TvRemotePadId, m_LastTvRemoteButtons, true, true);
  ReadKeyboardIntoState();
  UpdateTvRemoteHoldConfirm();
#endif

  if (m_MenuConfirmLatchFrames > 0) {
    m_MenuConfirmLatchFrames--;
  }
}
