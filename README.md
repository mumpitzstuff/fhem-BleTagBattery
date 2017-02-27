<h3>BleTagBattery</h3>
<ul>
  <u><b>BleTagBattery - Update batteryLevel for all BLE tags</b></u>
  <br>
  This module can be used to update the Reading batteryLevel for all bluetooth low energy tags registered as PRESENCE devices.<br><br>
  <b>Requirements:</b><br>
  <ul>
    <li>Gattool is required to use this module. Be sure that bluez is installed (sudo apt-get install bluez).</li>
    <li>BLE tags must be registered as PRESENCE devices of type lan-bluetooth.</li>
  </ul>
  <br><br>
  <b>Installation:</b>
  <ul>
    <li>be sure that bluez is installed: sudo apt-get install bluez</li>
    <li>add the new update site: update add http://<i></i>raw.githubusercontent.com/mumpitzstuff/fhem-BleTagBattery/master/controls_bletagbattery.txt</li>
    <li>run the update and wait until finished: update all</li>
    <li>restart fhem: shutdown restart</li>
    <li>define a new device: define &lt;name of device&gt; BleTagBattery</li>
  </ul>
  <br><br>
  <b>Usage:</b>
  The module automatically try to reach all BLE tags every 6 hours and to update the reading batteryLevel for each tag directly within the tag device. You 
  can manually trigger the update with: set <name of device> statusRequest.<br>
  <br><br>
  <b>Supported BLE tags:</b>
  <ul>
    <li>Gigaset G-Tag</li>
    <li>nut (possible supported but not tested)</li>
    <li>more to come</li>
  </ul>
</ul>
