#! /usr/bin/env perl
# Copyright 2015-2016 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the OpenSSL license (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html

package recipes::checkhandshake;

use OpenSSL::Test qw/:DEFAULT cmdstr srctop_file srctop_dir bldtop_dir/;
use OpenSSL::Test::Utils;
use TLSProxy::Proxy;

use Exporter;
our @ISA = 'Exporter';
our @EXPORT = qw(@handmessages @extensions checkhandshake);

use constant {
    DEFAULT_HANDSHAKE => 1,
    OCSP_HANDSHAKE => 2,
    RESUME_HANDSHAKE => 4,
    CLIENT_AUTH_HANDSHAKE => 8,
    RENEG_HANDSHAKE => 16,

    ALL_HANDSHAKES => 31
};

use constant {
    #DEFAULT ALSO INCLUDES SESSION_TICKET_SRV_EXTENSION
    DEFAULT_EXTENSIONS => 0x00000003,
    SESSION_TICKET_SRV_EXTENSION => 0x00000002,
    SERVER_NAME_CLI_EXTENSION => 0x00000004,
    SERVER_NAME_SRV_EXTENSION => 0x00000008,
    STATUS_REQUEST_CLI_EXTENSION => 0x00000010,
    STATUS_REQUEST_SRV_EXTENSION => 0x00000020,
    ALPN_CLI_EXTENSION => 0x00000040,
    ALPN_SRV_EXTENSION => 0x00000080,
    SCT_CLI_EXTENSION => 0x00000100,
    RENEGOTIATE_CLI_EXTENSION => 0x00000200
};

our @handmessages = ();
our @extensions = ();

sub checkhandshake($$$$)
{
    my ($proxy, $handtype, $exttype, $testname) = @_;

    subtest $testname => sub {
        my $loop = 0;
        my $numtests;
        my $extcount;
        my $clienthelloseen = 0;

        #First count the number of tests
        for ($numtests = 0; $handmessages[$loop][1] != 0; $loop++) {
            $numtests++ if (($handmessages[$loop][1] & $handtype) != 0);
        }

        #Add number of extensions we check plus 2 for the number of messages
        #that contain extensions
        $numtests += $#extensions + 2;
        #In a renegotiation we will have double the number of extension tests
        if (($handtype & RENEG_HANDSHAKE) != 0) {
            $numtests += $#extensions + 2;
        }
        #In TLS1.3 there are 3 messages with extensions (and no renegotiations)
        $numtests += 1 if ($proxy->is_tls13());

        plan tests => $numtests;

        my $nextmess = 0;
        my $message = undef;
        for ($loop = 0; $handmessages[$loop][1] != 0; $loop++) {
            next if (($handmessages[$loop][1] & $handtype) == 0);
            if (scalar @{$proxy->message_list} > $nextmess) {
                $message = ${$proxy->message_list}[$nextmess];
                $nextmess++;
            } else {
                $message = undef;
            }
            if (!defined $message) {
                fail("Message type check. Got nothing, expected "
                     .$handmessages[$loop][0]);
                next;
            } else {
                ok($message->mt == $handmessages[$loop][0],
                   "Message type check. Got ".$message->mt
                   .", expected ".$handmessages[$loop][0]);
            }

            next if ($message->mt() != TLSProxy::Message::MT_CLIENT_HELLO
                    && $message->mt() != TLSProxy::Message::MT_SERVER_HELLO
                    && $message->mt() !=
                       TLSProxy::Message::MT_ENCRYPTED_EXTENSIONS);

            if ($message->mt() == TLSProxy::Message::MT_CLIENT_HELLO) {
                #Add renegotiate extension we will expect if renegotiating
                $exttype |= RENEGOTIATE_CLI_EXTENSION if ($clienthelloseen);
                $clienthelloseen = 1;
            }
            #Now check that we saw the extensions we expected
            my $msgexts = $message->extension_data();

            for (my $extloop = 0, $extcount = 0; $extensions[$extloop][2] != 0;
                                $extloop++) {
                next if ($message->mt() != $extensions[$extloop][0]);
                ok (($extensions[$extloop][2] & $exttype) == 0
                      || defined ($msgexts->{$extensions[$extloop][1]}),
                    "Extension presence check (Message: ".$message->mt()
                    ." Extension: ".($extensions[$extloop][2] & $exttype).", "
                    .$extloop.")");
                $extcount++ if (($extensions[$extloop][2] & $exttype) != 0);
             }
            ok($extcount == keys %$msgexts, "Extensions count mismatch ("
                                            .$extcount.", ".(keys %$msgexts)
                                            .")");
        }
    }
}

1;