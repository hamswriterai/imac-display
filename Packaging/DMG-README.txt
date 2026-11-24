iMac Display - use a 5K iMac as a second screen for another Mac

Install: drag BOTH apps to /Applications (or just run them from here) on every Mac you use.

On the iMac (the screen):
  Open "iMac Display Receiver". It goes fullscreen and waits, showing this iMac's address. Esc or Cmd-Q quits.

On the MacBook (the computer):
  Open "iMac Display Sender" (menu bar icon, no Dock icon).
  First launch: allow Screen Recording in System Settings > Privacy & Security, then open it again.
  A new display appears: arrange it in System Settings > Displays.
  Menu bar icon > Settings...: enter the iMac's address (shown on the receiver's waiting screen), quality, frame rate etc.
  Leave the address empty to find the iMac automatically. Settings are remembered; saving restarts the sender.
  With a direct Ethernet cable, enter the iMac's 169.254.x.x address.

Apps are not notarized. If macOS says it can't verify the developer:
  right-click the app > Open (first time only), or run:  xattr -dr com.apple.quarantine "/Applications/iMac Display Sender.app"
