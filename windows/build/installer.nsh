; Uninstall: remove the phone-link registration main.js writes (Settings > Default apps entry).
!macro customUnInstall
  DeleteRegKey HKCU "Software\Classes\N2ITPhone.URL"
  DeleteRegKey HKCU "Software\N2IT\N2ITPhone"
  DeleteRegValue HKCU "Software\RegisteredApplications" "N2IT Phone"
!macroend
