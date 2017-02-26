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

my $version = "0.0.1";


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

    foreach my $d(sort keys %{$modules{BleTagBattery}{defptr}}) {
        my $hash = $modules{BleTagBattery}{defptr}{$d};
        $hash->{VERSION} = $version;
    }
    
    return undef;
}

sub BleTagBattery_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "too few parameters: define <name> BleTagBattery" if ( @a != 2 );

    my $name = $a[0];

    #my $def = $modules{BleTagBattery}{defptr};
  
    #return "BleTagBattery device already defined as $def->{NAME}." if ( defined($def) ); 
    
    $hash->{VERSION} = $version;

    $modules{BleTagBattery}{defptr} = $hash;
    readingsSingleUpdate( $hash, "state", "initialized", 0 );
    
    RemoveInternalTimer( $hash );

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


    RemoveInternalTimer( $hash );

    InternalTimer( gettimeofday() + 86400 + int(rand(30)), "BleTagBattery_stateRequestTimer", $hash, 1 );
    
    if ( !IsDisabled($name) ) {
        readingsSingleUpdate( $hash, "state", "active", 1 );

        BleTagBattery_Run( $hash );
    } else {
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }

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
                                                     "BleTagBattery_BlockingDone", 60, 
                                                     "BleTagBattery_BlockingAborted", $hash );
    } else {
        Log3 $name, 4, "Sub BleTagBattery_Run ($name) - blocking call already running";    
    }
    
    return undef;
}

sub BleTagBattery_BlockingRun($) {
    my $name         = shift;
    my $hash         = $defs{$name};
    #my $targetHash;
    my $batteryLevel = "";
    my $result;
    my $device;
    my $deviceName;
    my $deviceList;
    my $deviceAddress = "";
    
    $result = fhem( "list MODE=lan-bluetooth" );
    
    while ( $result =~ m/([^\s]+)/g ) {    
        $device = $1;
        
        Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device found. device: $device";
        
        $deviceList = fhem( "list $device" );
        
        if ( $deviceList =~ /STATE\s+present/ ) {        
            if ( $deviceList =~ m/device_name\s+(.+)/ ) {
                $deviceName = $1;
                
                Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device name: $deviceName";
                
                if ( $deviceList =~ m/ADDRESS\s+([^\s]+)/ ) {
                    $deviceAddress = $1;
                
                    Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - device address: $deviceAddress";
            
                    if ( $deviceName eq "Gigaset G-tag" ) {
                        $batteryLevel = BleTagBattery_convertStringToU8( BleTagBattery_readSensorValue( $name, $deviceAddress, "--handle=0x001b", "public" ) );
                        
                        fhem( "setreading $device batteryLevel $batteryLevel" );
                        
                        Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - setreading $device batteryLevel $batteryLevel";
                        
                        #$targetHash = $defs{$device};
                        
                        #Log3 $name, 4, "Sub BleTagBattery_BlockingRun ($name) - reading update: $targetHash->{NAME}";
                        #readingsSingleUpdate( $targetHash, "batteryLevel", $batteryLevel, 1 );
                    }
                    elsif ( $deviceName eq "nut" ) {
                        $batteryLevel = BleTagBattery_convertStringToU8( BleTagBattery_readSensorValue( $name, $deviceAddress, "--uuid=0x2a19", "public" ) );
                        
                        fhem( "setreading $device batteryLevel $batteryLevel" );
                        
                        #$targetHash = $defs{$device};
                        #readingsSingleUpdate( $targetHash, "batteryLevel", $batteryLevel, 1 );
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
            
            RemoveInternalTimer( $hash );

            InternalTimer( gettimeofday() + 900 + int(rand(30)), "BleTagBattery_stateRequestTimer", $hash, 1 );
        }
    }
    
    return $name;
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
    while ( ($loop < 10) && ("" eq $value) );

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
    my $name = shift;
    my $hash = $defs{$name};

    delete($hash->{helper}{RUNNING_PID});

    Log3 $name, 4, "Sub BleTagBattery_BlockingDone ($name) - helper disabled. abort" if ( $hash->{helper}{DISABLED} );
    return if ( $hash->{helper}{DISABLED} );

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
