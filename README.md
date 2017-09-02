# iWptBrowser
wkWebView browser shell for iOS WebPagetest agent (integrates with wptagent)

The application must be compiled locally and installed on devices that are linked to your developer account so that the remote inspector interface is available for remote debugging (can not work from an app store build).

## Requirements
* Physical device (does not currently work with the simulator)
* iOS 9 or later
* a tethered host to run testing from with [wptagent](https://github.com/WPO-Foundation/wptagent) installed (can be Mac or Linux - Raspberry Pi's are recommended).  If using a raspberry pi, one pi per phone is recommended.

## Device Set-up
iOS devices should be configured as [supervised devices](https://www.howtogeek.com/252286/how-to-put-an-iphone-or-ipad-into-supervised-mode-to-unlock-powerful-management-features/) and set up to run in single app mode (with iWptBrowser as the single app).  That way it will automatically recover and restart the shell after any crashes or reboots.

## Tethered host configuration
