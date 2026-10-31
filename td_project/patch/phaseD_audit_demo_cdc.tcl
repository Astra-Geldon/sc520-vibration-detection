# Independent physical-flight audit; must not modify the production TD session.
source [file join [file dirname [info script]] td_device.tcl]
sc520_import_device
import_db demo_routed.db
source patch/check_demo_cdc.tcl
puts PHASE_D_DONE
exit 0
