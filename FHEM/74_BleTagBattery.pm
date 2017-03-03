###############################################################################
#
#  (c) 2017 Copyright: Achim Winkler
#  All rights reserved
#
###############################################################################


package main;

use strict;
use warnings;
use Blocking;

my $version = "0.0.3";


# Declare functions
sub BleTagBattery_Initialize($);
sub BleTagBattery_Define($$);
sub BleTagBattery_Undef($$);
sub BleTagBattery_Attr(@);
sub BleTagBattery_stateRequest($);
sub BleTagBattery_stateRequestTimer($);
sub BleTagBattery_Set($$@);
sub BleTagBattery_Run($);
sub BleTagBattery_BlockingRun($);
sub BleTagBattery_readSensorValue($$$$);
sub BleTagBattery_convertStringToU8($);
sub BleTagBattery_BlockingDone($);
sub BleTagBattery_BlockingAborted($);




sub BleTagBattery_Initialize($) {
    my $hash = shift;

    
    $hash->{SetFn}      = "BleTagBattery_Set";
    $hash->{DefFn}      = "BleTagBattery_Define";
    $hash->{UndefFn}    = "BleTagBattery_Undef";
    $hash->{AttrFn}     = "BleTagBattery_Attr";
    $hash->{AttrList}   = "disable:1 ".
                          "hciDevice:hci0,hci1,hci2 ".
                          $readingFnAttributes;

    $hash->{VERSION} = $version;
    
    return undef;
}

sub BleTagBattery_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "too few parameters: define <name> BleTagBattery" if ( @a != 2 );

    my $name = $a[0];

    my $d = $modules{BleTagBattery}{defptr};
    return "BleTagBattery device already defined as ".$d->{NAME} if ( defined($d) ); 
    
    $hash->{VERSION} = $version;

    $modules{BleTagBattery}{defptr} = $hash;
    readingsSingleUpdate( $hash, "state", "initialized", 0 );
    
    if ( $init_done ) {
        BleTagBattery_stateRequestTimer( $hash );
    } else {
        InternalTimer( gettimeofday() + int(rand(30)) + 15, "BleTagBattery_stateRequestTimer", $hash, 0 );
    }

    Log3 $name, 3, "Sub BleTagBattery_Define ($name) - defined";

    return undef;
}

sub BleTagBattery_Undef($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};


    RemoveInternalTimer( $hash );
    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined($hash->{helper}{RUNNING_PID}) ); 

    delete( $modules{BleTagBattery}{defptr} );
    Log3 $name, 3, "Sub BleTagBattery_Undef ($name) - device deleted";
    
    return undef;
}

sub BleTagBattery_Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};


    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate( $hash, "state", "disabled", 1 );
            
            Log3 $name, 3, "BleTagBattery_Attr ($name) - device disabled";
        }
        elsif ( $cmd eq "del" ) {
            readingsSingleUpdate( $hash, "state", "active", 1 );
            
            Log3 $name, 3, "Sub BleTagBattery_Attr ($name) - device enabled";
        }
    }

    return undef;
}

sub BleTagBattery_stateRequest($) {
    my $hash = shift;
    my $name = $hash->{NAME};


    if ( !IsDisabled($name) ) {
        readingsSingleUpdate( $hash, "state", "active", 1 );

        BleTagBattery_Run( $hash );
    } else {
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }
    
    Log3 $name, 5, "Sub BleTagBattery_stateRequest ($name) - state request called";
    
    return undef;
}

sub BleTagBattery_stateRequestTimer($) {
    my $hash = shift;
    my $name = $hash->{NAME};


    if ( !IsDisabled($name) ) {
        readingsSingleUpdate( $hash, "state", "active", 1 );

        BleTagBattery_Run( $hash );
    } else {
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }
    
    InternalTimer( gettimeofday() + 21600 + int(rand(30)), "BleTagBattery_stateRequestTimer", $hash, 1 );

    Log3 $name, 5, "Sub BleTagBattery_stateRequestTimer ($name) - state request timer called";
    
    return undef;
}

sub BleTagBattery_Set($$@) {
    my ($hash, $name, @aa)  = @_;
    my ($cmd, $arg)         = @aa;

    
    if ( $cmd eq 'statusRequest' ) {
        BleTagBattery_stateRequest( $hash );
    } else {
        my $list = "statusRequest:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }

    return undef;
}

sub BleTagBattery_Run($) {
    my ( $hash, $cmd )  = @_;
    my $name            = $hash->{NAME};
    
    
    if ( not exists($hash->{helper}{RUNNING_PID}) ) {
        Log3 $name, 4, "Sub BleTagBattery_Run ($name) - start blocking call";
    
        $hash->{helper}{RUNNING_PID} = BlockingCall( "BleTagBattery_BlockingRun", $name, 
                                                     "BleTagBattery_BlockingDone", 240, 
                                                     "BleTagBattery_BlockingAborted", $hash );
    } else {
        Log3 $name, 4, "Sub BleTagBattery_Run ($name) - blocking call already running";    
    }
    
    return undef;
}

sub BleTagBattery_BlockingRun($) {
    my $name           = shift;
    my $hash           = $defs{$name};
    my $batteryLevel;
    my $setting;
    my $result;
    my $device;
    my $deviceName;
    my $deviceList;
    my $deviceAddress  = "";
    my $isSingleDevice = 0;
    my $ret            = "";
    
    $result = fhem( "list MODE=lan-bluetooth", 1 );
    
    if ( $result =~ /^Internals:/ ) {
        $isSingleDevice = 1;
    }
    
    while ( (0 == $isSingleDevice && $result =~ m/([^\s]+)/g) ||
            (1 == $isSingleDevice && $result =~ m/NAME\s+([^\s]+)/g) ) {    
        $device = $1;
        
        Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device found. device: $device";
        
        $deviceList = fhem( "list $device", 1 );
        
        if ( $deviceList =~ m/STATE\s+present/ ) {        
            if ( $deviceList =~ m/device_name\s+(.+)/ ) {
                $deviceName = $1;
                
                Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device name: $deviceName";
                
                if ( $deviceList =~ m/ADDRESS\s+([^\s]+)/ ) {
                    $deviceAddress = $1;
                    $batteryLevel = "";
                    $setting = "none";
                
                    Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device address: $deviceAddress";
            
                    # settings already available for this device?
                    if ( defined($hash->{helper}{$device}) ) {
                        Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - tag already saved in hash";
                        
                        $batteryLevel = BleTagBattery_convertStringToU8( BleTagBattery_readSensorValue( $name, $deviceAddress, "--uuid=0x2a19", $hash->{helper}{$device} ) );
                    } else {
                        # try to connect with public and store this setting if successful
                        Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - try to connect with public";
                            
                        $batteryLevel = BleTagBattery_convertStringToU8( BleTagBattery_readSensorValue( $name, $deviceAddress, "--uuid=0x2a19", "public" ) );
                        if ( "" ne $batteryLevel ) {
                            $setting = "public";
                        } else {
                            # try to connect with random and store this setting if successful
                            Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - try to connect with random";
                            
                            $batteryLevel = BleTagBattery_convertStringToU8( BleTagBattery_readSensorValue( $name, $deviceAddress, "--uuid=0x2a19", "random" ) );
                            if ( "" ne $batteryLevel ) {
                                $setting = "random";
                            }
                        }
                    }
                    
                    if ( "" eq $batteryLevel ) {
                        Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - tag not supported";
                    } else {
                        $ret .= "|$device|$batteryLevel|$setting";
                    }
                    
                    Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - processing gatttool response for device $device. batteryLevel: $batteryLevel";
                } else {
                    Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device address not found.";
                }
            } else {
                Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device name not found.";
            }
        } else {
            Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device not present.";
        }
    }
    
    return $name.$ret;
}

sub BleTagBattery_readSensorValue($$$$) {
    my ($name, $mac, $service, $type ) = @_;
    my $hci                            = AttrVal( $name, "hciDevice", "hci0" );
    my $result;
    my $loop                           = 0;
    my $value                          = "";

    do {
        # try to read the value from sensor
        $result = qx( gatttool -i $hci -t $type -b $mac --char-read $service 2>&1 );
        Log3 $name, 4, "Sub BleTagBattery_readSensorValue ($name) - call gatttool char read loop: $loop, result: $result";
        
        if ( $result =~ /handle\:.*value\:(.*)/ ) {
            $value = $1;
         } elsif ( $result =~ /Characteristic value\/descriptor\:(.*)/ ) {
            $value = $1;
        } else {
            $loop++;
        }
    }
    while ( ($loop < 5) && ("" eq $value) );

    if ( "" ne $value ) {
        # remove spaces
        $value =~ s/\s//g;
        
        Log3 $name, 4, "Sub BleTagBattery_readSensorValue ($name) - processing gatttool response: $value";

        return $value;
    } else {
        Log3 $name, 4, "Sub BleTagBattery_readSensorValue ($name) - invalid gatttool response";
        
        # return empty string in case of an error
        return "";
    }
}

sub BleTagBattery_convertStringToU8($) {
    $_ = shift;

    if ( "" ne $_ ) {
        # convert string to U8
        return hex($_);
    } else {
        return "";
    }
}

sub BleTagBattery_BlockingDone($) {
    my @param = split( "\\|", shift );
    my $name = $param[0];
    my $hash = $defs{$name};
    my $i;
    
    delete($hash->{helper}{RUNNING_PID});

    Log3 $name, 4, "Sub BleTagBattery_BlockingDone ($name) - helper disabled. abort" if ( $hash->{helper}{DISABLED} );
    return if ( $hash->{helper}{DISABLED} );
    
    for ($i = 0; $i < ((scalar(@param) - 1) / 3); $i++) {
        my $targetHash = $defs{$param[1 + ($i * 3)]};
        
        if ( "none" ne $param[3 + ($i * 3)] ) {
            Log3 $name, 4, "Sub BleTagBattery_BlockingDone ($name) - setting saved into hash: $param[3 + ($i * 3)]";
        
            $hash->{helper}{$param[1 + ($i * 3)]} = $param[3 + ($i * 3)];
        }
        
        Log3 $name, 4, "Sub BleTagBattery_BlockingDone ($name) - set readings batteryLevel and battery of device: $param[1 + ($i * 3)]";
        
        if ( defined($targetHash) ) {
            readingsBeginUpdate( $targetHash );
            readingsBulkUpdate( $targetHash, "batteryLevel", $param[2 + ($i * 3)] );
            readingsBulkUpdate( $targetHash, "battery", ($param[2 + ($i * 3)] > 15 ? "ok" : "low") );
            readingsEndUpdate( $targetHash, 1 );
        } else {
            Log3 $name, 4, "Sub BleTagBattery_BlockingDone ($name) - target hash not found.";
        }
    }

    Log3 $name, 4, "Sub BleTagBattery_BlockingDone ($name) - done";
    
    return undef;
}

sub BleTagBattery_BlockingAborted($) {
    my $hash = shift;
    my $name = $hash->{NAME};

    delete( $hash->{helper}{RUNNING_PID} );
    
    Log3 $name, 3, "($name) Sub BleTagBattery_BlockingAborted - BlockingCall process terminated unexpectedly: timeout";
    
    return undef;
}

1;








=pod
=item device
=item summary       Modul to retrieve the battery state from bluetooth low energy tags
=item summary_DE    Modul um den Batteriestatus von Bluetooth Low Energy Tags auszulesen

=begin html

<a name="BleTagBattery"></a>

=end html
=begin html_DE

<a name="BleTagBattery"></a>

=end html_DE
=cut
