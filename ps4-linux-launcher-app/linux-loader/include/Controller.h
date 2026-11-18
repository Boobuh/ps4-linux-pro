// License: GPL-3.0

#ifndef CONTROLLER_H
#define CONTROLLER_H

#include <orbis/_types/pad.h>

#include "PadInputCommon.h"

// Home / PS: intercepted-only pulse or PlayStation bit (see PadInputCommon.h).
constexpr unsigned int PS4LINUX_TV_REMOTE_HOME_MASK =
    ORBIS_PAD_BUTTON_INTERCEPTED | ORBIS_PAD_BUTTON_PLAYSTATION;

// Bravia colored Options key → ORBIS_TRIANGLE (0x1000). Not Enter; must not open settings either.
constexpr unsigned int PS4LINUX_TV_REMOTE_OPTIONS_KEY_MASK = ORBIS_PAD_BUTTON_TRIANGLE;

// If center OK ever reaches the PS4 it is often 0x8 (ORBIS Options) or Cross/L3 on USER_STD — not 0x1000.
constexpr unsigned int PS4LINUX_TV_REMOTE_OK_MASK =
    ORBIS_PAD_BUTTON_OPTIONS | ORBIS_PAD_BUTTON_CROSS | ORBIS_PAD_BUTTON_CIRCLE |
    ORBIS_PAD_BUTTON_L3 | ORBIS_PAD_BUTTON_R3 | ORBIS_PAD_BUTTON_TOUCH_PAD | 0x00010000u;

constexpr unsigned int PS4LINUX_TV_REMOTE_DPAD_MASK =
    ORBIS_PAD_BUTTON_UP | ORBIS_PAD_BUTTON_DOWN | ORBIS_PAD_BUTTON_LEFT | ORBIS_PAD_BUTTON_RIGHT;

class Controller {
public:
  Controller();
  ~Controller();

  void Update();

  unsigned int GetCurrentButtonsPressed();
  void SetCurrentButtonsPressed(unsigned int p_Buttons);
  unsigned int GetCurrentButtonsReleased();
  void SetCurrentButtonsReleased(unsigned int p_Buttons);

  bool GetButtonHold(unsigned int p_Filter);
  bool GetButtonPressed(unsigned int p_Filter);
  bool GetButtonReleased(unsigned int p_Filter);

  bool HasAnyInputDevice() const;
  bool HasTvRemotePad() const { return m_TvRemotePadId >= 0; }
  unsigned int GetLastStandardRawButtons() const { return m_LastStandardButtons; }
  unsigned int GetLastTvRemoteRawButtons() const { return m_LastTvRemoteButtons; }

  /// Enter / OK: Cross or Circle per system setting; TV remote OK maps to the same (Home excluded).
  bool GetMenuConfirmPressed() const;
  void ConsumeMenuConfirm();

private:
  void EnsureUserServiceReady();
  void TryAttachInputDevices();
  void ReadKeyboardIntoState();
  void ApplyPadSample(unsigned int actual, unsigned int &lastButtons, bool isTvRemote);
  void MergePadRead(int handle, unsigned int &lastButtons, bool allowDisconnected, bool isTvRemote);
  void MergeStandardPadRead(int handle, unsigned int &lastButtons, OrbisPadData *outLatestState);
  unsigned int AdjustFaceButtonFilter(unsigned int filter) const;
  static unsigned int ButtonsWithStickAsDpad(const OrbisPadData &data);

  int m_UserId;
  int m_PadId;
  /// HDMI CEC OK often arrives on system-user standard port, not REMOTE_CONTROL dpad handle.
  int m_SystemStdPadId;
  int m_TvRemotePadId;
  bool m_TvRemotePadOwned;
  int m_KeyboardHandle;
  bool m_KeyboardKeyDown[128];

  unsigned int m_LastStandardButtons;
  unsigned int m_LastSystemStdButtons;
  unsigned int m_LastTvRemoteButtons;

  unsigned int m_ButtonsPressed;
  unsigned int m_ButtonsReleased;
  unsigned int m_CurrentButtons;
  unsigned int m_ButtonsHold;

  bool m_EnterIsCross;

  /// TV OK is often a single-frame edge; keep confirm alive for several frames.
  uint8_t m_MenuConfirmLatchFrames;

  void PulseMenuConfirm();
  void UpdateTvRemoteHoldConfirm();

  OrbisPadData m_PadData;
  uint16_t m_TvRemoteDownHoldFrames;
  bool m_TvRemoteDownConfirmFired;
};

#endif
