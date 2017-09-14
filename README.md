# iWptBrowser
wkWebView browser shell for iOS WebPagetest agent (integrates with wptagent)

The application must be compiled locally and installed on devices that are linked to your developer account so that the remote inspector interface is available for remote debugging (can not work from an app store build).

**The browser will appear upside down and the display will dim - this is normal and expedted!**
By running the browser upside down it allows the code to rotate the display to landscape mode on-demand.  Dimming of the display is to reduce heat and power drain by running the backlight as low as possible.

## Requirements
* Physical device (does not currently work with the simulator)
* iOS 9 or later
* A Mac with [Apple configurator 2](https://itunes.apple.com/us/app/apple-configurator-2/id1037126344?mt=12) for configuring supervised mode on the devices. The mac is only needed for setup and not for use during testing.
* a tethered host to run testing from with [wptagent](https://github.com/WPO-Foundation/wptagent) installed (can be Mac or Linux - Raspberry Pi's are recommended).  If using a raspberry pi, one pi per phone is recommended.

## Device Set-up
iOS devices should be configured as [supervised devices](https://www.howtogeek.com/252286/how-to-put-an-iphone-or-ipad-into-supervised-mode-to-unlock-powerful-management-features/) and set up to run in single app mode (with iWptBrowser as the single app).  That way it will automatically recover and restart the shell after any crashes or reboots.

It is recommended that the device be oriented in portrait mode or landscape-right so that the browser can be toggled between portrait and landscape progromatically.

For a full setup walkthrough refer to the [walkthrough guide](docs/walkthrough.md).
