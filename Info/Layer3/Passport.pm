# SNMP::Info::Layer3::Passport
# Eric Miller <eric@jeneric.org>
# $Id$
#
# Copyright (c) 2004 Eric Miller, Max Baker
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Santa Cruz nor the 
#       names of its contributors may be used to endorse or promote products 
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package SNMP::Info::Layer3::Passport;
$VERSION = 1.0;

use strict;

use Exporter;
use SNMP::Info;
use SNMP::Info::Bridge;
use SNMP::Info::SONMP;
use SNMP::Info::RapidCity;

use vars qw/$VERSION $DEBUG %GLOBALS %FUNCS $INIT %MIBS %MUNGE/;

@SNMP::Info::Layer3::Passport::ISA = qw/SNMP::Info SNMP::Info::Bridge SNMP::Info::SONMP SNMP::Info::RapidCity Exporter/;
@SNMP::Info::Layer3::Passport::EXPORT_OK = qw//;

%MIBS = (
         %SNMP::Info::MIBS,
         %SNMP::Info::Bridge::MIBS,
         %SNMP::Info::SONMP::MIBS,
         %SNMP::Info::RapidCity::MIBS,
         'OSPF-MIB'     => 'ospfRouterId',
        );

%GLOBALS = (
            %SNMP::Info::GLOBALS,
            %SNMP::Info::Bridge::GLOBALS,
            %SNMP::Info::SONMP::GLOBALS,
            %SNMP::Info::RapidCity::GLOBALS,            
            'router_ip' => 'ospfRouterId'
           );

%FUNCS = (
          %SNMP::Info::FUNCS,
          %SNMP::Info::Bridge::FUNCS,
          %SNMP::Info::SONMP::FUNCS,
          %SNMP::Info::RapidCity::FUNCS,
          'i_index2'            => 'ifIndex',
          'i_mac2'              => 'ifPhysAddress',
          'i_description2'      => 'ifDescr',
          'i_name2'             => 'ifName',
          'ip_index2'           => 'ipAdEntIfIndex',
           # From RFC1213-MIB
          'at_index'    => 'ipNetToMediaIfIndex',
          'at_paddr'    => 'ipNetToMediaPhysAddress',
          'at_netaddr'  => 'ipNetToMediaNetAddress',
          'i_name2'        => 'ifName'
         );
         
%MUNGE = (
            %SNMP::Info::MUNGE,
            %SNMP::Info::Bridge::MUNGE,
            %SNMP::Info::SONMP::MUNGE,
            %SNMP::Info::RapidCity::MUNGE,
            'i_mac2' => \&SNMP::Info::munge_mac,
            'at_paddr' => \&SNMP::Info::munge_mac,
         );

sub model {
    my $passport = shift;
    my $desc = $passport->description();
    return undef unless defined $desc;

    return '8603' if ($desc =~ /8603/);
    return '8606' if ($desc =~ /8606/);
    return '8610co' if ($desc =~ /8610co/);
    return '8610' if ($desc =~ /8610/);
    
    return $desc;
}

sub vendor {
    return 'nortel';
}

sub os {
    return 'passport';
}

sub os_ver {
    my $passport = shift;
    my $descr = $passport->description();
    return undef unless defined $descr;

    if ($descr =~ m/(\d+\.\d+\.\d+\.\d+)/){
        return $1;
    }
    return undef;
}

sub i_index {
    my $passport = shift;
    my $i_index = $passport->i_index2();
    my $vlan_index = $passport->rc_vlan_if();
    my $cpu_index = $passport->rc_cpu_ifindex();
    my $virt_ip = $passport->rc_virt_ip();
    
    my %if_index;
    foreach my $iid (keys %$i_index){
        my $index = $i_index->{$iid};
        next unless defined $index;

        $if_index{$iid} = $index;
    }

    # Get VLAN Virtual Router Interfaces
    foreach my $vid (keys %$vlan_index){
        my $v_index = $vlan_index->{$vid};
        next unless defined $v_index;
        next if $v_index == 0;

        $if_index{$v_index} = $v_index;
    }

    # Get CPU Ethernet Interfaces
    foreach my $cid (keys %$cpu_index){
        my $c_index = $cpu_index->{$cid};
        next unless defined $c_index;
        next if $c_index == 0;

        $if_index{$c_index} = $c_index;
    }

    # Check for Virtual Mgmt Interface
    unless ($virt_ip eq '0.0.0.0') {
        # Make up an index number, 1 is not reserved AFAIK
        $if_index{1} = 1;
    }

    return \%if_index;
}

sub interfaces {
    my $passport = shift;
    my $i_index = $passport->i_index();
    my $vlan_id = $passport->rc_vlan_id();
    my $vlan_index = $passport->rc_vlan_if();
    my $model = $passport->model();

    my %reverse_vlan = reverse %$vlan_index;
    
    my %if;
    foreach my $iid (keys %$i_index){
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ($index == 1) {
            $if{$index} = 'CPU.Virtual';
        }

        elsif (($index == 192) and ($model eq '8603')) {
            $if{$index} = 'CPU3';
        }

        elsif ($index == 320) {
            $if{$index} = 'CPU5';
        }

        elsif ($index == 384) {
            $if{$index} = 'CPU6';
        }

        elsif ($index > 2000) {
            my $vlan_index = $reverse_vlan{$iid};
            my $v_id = $vlan_id->{$vlan_index};
            next unless defined $v_id;
            my $v_port = 'V'."$v_id";
            $if{$index} = $v_port;
        }           

        else {
            my $port = ($index % 64) + 1;
            my $slot = int($index / 64);

            my $slotport = "$slot.$port";
            $if{$iid} = $slotport;
        }

    }
    return \%if;
}

sub i_mac {
    my $passport = shift;
    my $i_mac = $passport->i_mac2();
    my $vlan_mac = $passport->rc_vlan_mac();
    my $vlan_index = $passport->rc_vlan_if();
    my $cpu_mac = $passport->rc_cpu_mac();
    my $chassis_base_mac = $passport->rc_base_mac();
    my $virt_ip = $passport->rc_virt_ip();

    my %if_mac;
    foreach my $iid (keys %$i_mac){
        my $mac = $i_mac->{$iid};
        next unless defined $mac;

        $if_mac{$iid} = $mac;
    }

    # Get VLAN Virtual Router Interfaces
    foreach my $iid (keys %$vlan_mac){
        my $v_mac = $vlan_mac->{$iid};
        my $v_id  = $vlan_index->{$iid};
        next unless defined $v_mac;

        $if_mac{$v_id} = $v_mac;
    }

    # Get CPU Ethernet Interfaces
    foreach my $iid (keys %$cpu_mac){
        my $mac = $cpu_mac->{$iid};
        next unless defined $mac;

        $if_mac{$iid} = $mac;
    }

    # Check for Virtual Mgmt Interface
    unless ($virt_ip eq '0.0.0.0'){
        my @virt_mac = split /:/, $chassis_base_mac;
        $virt_mac[0] = hex($virt_mac[0]);
        $virt_mac[1] = hex($virt_mac[1]);
        $virt_mac[2] = hex($virt_mac[2]);
        $virt_mac[3] = hex($virt_mac[3]);
        $virt_mac[4] = hex($virt_mac[4]) + 0x03;
        $virt_mac[5] = hex($virt_mac[5]) + 0xF8;

        my $mac = join(':',map { sprintf "%02x",$_ } @virt_mac);

        $if_mac{1} = $mac;
    }

    return \%if_mac;
}

sub i_description {
    my $passport = shift;
    my $i_descr = $passport->i_description2();
    my $v_descr = $passport->rc_vlan_name();
    my $vlan_index = $passport->rc_vlan_if();

    my %descr;
    foreach my $iid (keys %$i_descr){
        my $if_descr = $i_descr->{$iid};
        next unless defined $if_descr;

        $descr{$iid} = $if_descr;
    }

    # Get VLAN Virtual Router Interfaces
    foreach my $vid (keys %$v_descr){
        my $vl_descr = $v_descr->{$vid};
        my $v_id  = $vlan_index->{$vid};
        next unless defined $vl_descr;

        $descr{$v_id} = $vl_descr;
    }
    return \%descr;
}
    
sub i_name {
    my $passport = shift;
    my $i_index = $passport->i_index();
    my $rc_alias = $passport->rc_alias();
    my $i_name2  = $passport->i_name2();
    my $v_name = $passport->rc_vlan_name();
    my $vlan_index = $passport->rc_vlan_if();
    my $model = $passport->model();
    
    my %reverse_vlan = reverse %$vlan_index;

    my %i_name;
    foreach my $iid (keys %$i_index){
        
        if ($iid == 1) {
            $i_name{$iid} = 'CPU Virtual Management IP';
        }

        elsif (($iid == 192) and ($model eq '8603')) {
            $i_name{$iid} = 'CPU 3 Ethernet Port';
        }

        elsif ($iid == 320) {
            $i_name{$iid} = 'CPU 5 Ethernet Port';
        }

        elsif ($iid == 384) {
            $i_name{$iid} = 'CPU 5 Ethernet Port';
        }

        elsif ($iid > 2000) {
            my $vlan_index = $reverse_vlan{$iid};
            my $vlan_name = $v_name->{$vlan_index};
            next unless defined $vlan_name;

            $i_name{$iid} = $vlan_name;
        }           

        else {
            my $name = $i_name2->{$iid};
            my $alias = $rc_alias->{$iid};
            $i_name{$iid} = (defined $alias and $alias !~ /^\s*$/) ?
                        $alias : 
                        $name;
        }
    }

    return \%i_name;
}

sub ip_index {
    my $passport = shift;
    my $ip_index = $passport->ip_index2();
    my $cpu_ip = $passport->rc_cpu_ip();
    my $virt_ip = $passport->rc_virt_ip();

    my %ip_index;
    foreach my $ip (keys %$ip_index){
        my $iid  = $ip_index->{$ip};
        next unless defined $iid;
        
        $ip_index{$ip} = $iid;
    }

    # Get CPU Ethernet IP
    foreach my $cid (keys %$cpu_ip){
        my $c_ip = $cpu_ip->{$cid};
        next unless defined $c_ip;

        $ip_index{$c_ip} = $cid;
    }

    # Get Virtual Mgmt IP
    $ip_index{$virt_ip} = 1;
    
    return \%ip_index;
}

sub root_ip {
    my $passport = shift;
    my $rc_ip_addr = $passport->rc_ip_addr();
    my $rc_ip_type = $passport->rc_ip_type();
    my $virt_ip = $passport->rc_virt_ip();
    my $router_ip  = $passport->router_ip();
    my $sonmp_topo_port = $passport->sonmp_topo_port();
    my $sonmp_topo_ip = $passport->sonmp_topo_ip();

    # Return CLIP (CircuitLess IP)
    foreach my $iid (keys %$rc_ip_type){
        my $ip_type = $rc_ip_type->{$iid};
        next unless ((defined $ip_type) and ($ip_type =~ /circuitLess/i));
        my $ip = $rc_ip_addr->{$iid};
        next unless defined $ip;
                     
        return $ip;
    }

    # Return Management Virtual IP address
    return $virt_ip if ((defined $virt_ip) and ($virt_ip ne '0.0.0.0'));

    # Return OSPF Router ID
    return $router_ip if ((defined $router_ip) and ($router_ip ne '0.0.0.0'));

    # Otherwise Return SONMP Advertised IP Address    
    foreach my $entry (keys %$sonmp_topo_port){
        my $port = $sonmp_topo_port->{$entry};
        next unless $port == 0;
        my $ip = $sonmp_topo_ip->{$entry};
        return $ip if ((defined $ip) and ($ip ne '0.0.0.0'));
    }
    return undef;
}

# Required for SNMP::Info::SONMP
sub index_factor {
    return 64;
}

sub slot_offset {
    return 0;
}

sub port_offset {
    return 1;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::Passport - Perl5 Interface to Nortel Networks' Passport
8600 Series Switches

=head1 AUTHOR

Eric Miller (C<eric@jeneric.org>)

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $passport = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $passport->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Abstraction subclass for Nortel Networks' Passport 8600 Series Switches.  

These devices run Passport OS but have some of the same charactersitics as the Baystack family. 
For example, extended interface information is gleened from RAPID-CITY.

For speed or debugging purposes you can call the subclass directly, but not after determining
a more specific class using the method above. 

 my $passport = new SNMP::Info::Layer3::Passport(...);

=head2 Inherited Classes

=over

=item SNMP::Info

=item SNMP::Info::Bridge

=item SNMP::Info::SONMP

=item SNMP::Info::RapidCity

=back

=head2 Required MIBs

=over

=item OSPF-MIB

=item Inherited Classes' MIBs

See SNMP::Info for its own MIB requirements.

See SNMP::Info::Bridge for its own MIB requirements.

See SNMP::Info::SONMP for its own MIB requirements.

See SNMP::Info::RapidCity for its own MIB requirements.

OSPF-MIB is included in the archive at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $passport->model()

Returns the model extracted from B<sysDescr>

=item $passport->vendor()

Returns 'Nortel'

=item $passport->os()

Returns 'Passport'

=item $passport->os_ver()

Returns the software version extracted from B<sysDescr>

=item $passport->serial()

Returns (B<rcChasSerialNumber>)

=item $passport->root_ip()

Returns the primary IP used to communicate with the device.  Returns the first
found:  CLIP (CircuitLess IP), Management Virtual IP (B<rcSysVirtualIpAddr>),
OSPF Router ID (B<ospfRouterId>), SONMP Advertised IP Address.

=back

=head2 Overrides

=over

=item $passport->index_factor()

Required by SNMP::Info::SONMP.  Returns 64.

=item $passport->port_offset()

Required by SNMP::Info::SONMP.  Returns 1.

=item $passport->slot_offset()

Required by SNMP::Info::SONMP.  Returns 0.

=back

=head2 Globals imported from SNMP::Info

See documentation in SNMP::Info for details.

=head2 Globals imported from SNMP::Info::Bridge

See documentation in SNMP::Info::Bridge for details.

=head2 Global Methods imported from SNMP::Info::SONMP

See documentation in SNMP::Info::SONMP for details.

=head2 Global Methods imported from SNMP::Info::RapidCity

See documentation in SNMP::Info::RapidCity for details.

=head1 TABLE ENTRIES

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $passport->i_index()

Returns SNMP IID to Interface index.  Extends (B<ifIndex>) by adding the index of
the CPU virtual management IP (if present), each CPU Ethernet port, and each VLAN
to ensure the virtual router ports are captured.

=item $passport->interfaces()

Returns reference to the map between IID and physical Port.

Slot and port numbers on the Passport switches are determined by the formula:
port = (ifIndex % 64) + 1, slot = int(ifIndex / 64).

The physical port name is returned as slot.port.  CPU Ethernet ports are prefixed
with CPU and VLAN interfaces are returned as the VLAN ID prefixed with V.

=item $passport->i_mac()

MAC address of the interface.  Note this is just the MAC of the port, not anything
connected to it.

=item $passport->i_description()

Description of the interface. Usually a little longer single word name that is both
human and machine friendly.  Not always.

=item $passport->i_name()

Crosses rc_alias() (B<rcPortName>) with ifAlias() and returns the human set port
name if exists.

=item $passport->ip_index()

Maps the IP Table to the IID.  Extends (B<ipAdEntIfIndex>) by adding the index of
the CPU virtual management IP (if present) and each CPU Ethernet port.

=back

=head2 RFC1213 Arp Cache Table (B<ipNetToMediaTable>)

=over

=item $passport->at_index()

Returns reference to hash.  Maps ARP table entries to Interface IIDs 

(B<ipNetToMediaIfIndex>)

=item $passport->at_paddr()

Returns reference to hash.  Maps ARP table entries to MAC addresses. 

(B<ipNetToMediaPhysAddress>)

=item $passport->at_netaddr()

Returns reference to hash.  Maps ARP table entries to IPs 

(B<ipNetToMediaNetAddress>)

=back

=head2 Table Methods imported from SNMP::Info

See documentation in SNMP::Info for details.

=head2 Table Methods imported from SNMP::Info::Bridge

See documentation in SNMP::Info::Bridge for details.

=head2 Table Methods imported from SNMP::Info::SONMP

See documentation in SNMP::Info::SONMP for details.

=head2 Table Methods imported from SNMP::Info::RapidCity

See documentation in SNMP::Info::RapidCity for details.

=cut