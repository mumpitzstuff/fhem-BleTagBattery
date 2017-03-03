<h3>BleTagBattery</h3>
<ul>
  <u><b>BleTagBattery - Update batteryLevel for all BLE tags</b></u>
  <br>
  This module can be used to update the Reading batteryLevel and battery for all bluetooth low energy tags registered as PRESENCE devices.<br><br>
  <b>Requirements:</b><br>
  <ul>
    <li>Gattool is required to use this module. Be sure that bluez is installed (sudo apt-get install bluez).</li>
    <li>BLE tags must be registered as PRESENCE devices of type lan-bluetooth.</li>
  </ul>
  <br>
  <b>Installation:</b>
  <ul>
    <li>be sure that bluez is installed: sudo apt-get install bluez</li>
    <li>add the new update site: update add http://<i></i>raw.githubusercontent.com/mumpitzstuff/fhem-BleTagBattery/master/controls_bletagbattery.txt</li>
    <li>run the update and wait until finished: update all</li>
    <li>restart fhem: shutdown restart</li>
    <li>define a new device: define &lt;name of device&gt; BleTagBattery</li>
  </ul>
  <br>
  <b>Usage:</b>
  The module automatically try to reach all BLE tags every 6 hours and to update the reading batteryLevel and battery for each tag directly within the tag device. You 
  can manually trigger the update with: set &lt;name of device&gt; statusRequest.
  <br><br>
  <b>Pitfalls:</b>
  This module does not work well together with lepresenced on a single bluetooth dongle. In the best case lepresenced and this module should run on 
  separate bluetooth dongles. If this is not possible and you do not get any battery readings, try to activate the attribute verbose 5 within this 
  module and analyze the logfile. You can also try to increase the constant RETRY_SLEEP (start with high values like 30 and decrease the value if 
  possible) within the lepresenced deamon (stop the deamon, edit the lepresenced script and restart the deamon). This will give this module more time 
  to retrieve the battery value from the BLE tags before the lepresenced deamon try to restart the bluetooth dongle again. The more BLE tags you are using,
  the higher the value for RETRY_SLEEP should be.
  <br><br>
  <b>Attributes:</b>
  <ul>
    <li>disable: disable the BleTagBattery device</li>
    <li>hciDevice: bluetooth device (default: hci0)</li>
  </ul>
  <br>
  <b>Supported BLE tags:</b>
  <ul>
    <li>Gigaset G-Tag</li>
    <li>general handler for many other tags</li>
    <li>more to come</li>
  </ul>
</ul>
