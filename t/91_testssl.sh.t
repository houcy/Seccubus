#!/usr/bin/env perl
# Copyright 2017-2017 Frank Breedijk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ------------------------------------------------------------------------------
# This little script checks all files te see if they are perl files and if so
# ------------------------------------------------------------------------------

use strict;
use Algorithm::Diff qw( diff );
use Mojo::Base -strict;

use strict;

use Test::More;
use Test::Mojo;
use Data::Dumper;

use lib "lib";

use SeccubusV2;
use Seccubus::Findings;

# Prep kit
`mkdir tmp` unless -d "tmp";
if ( -d "tmp/testssl.sh" ) {
    pass("Updating testssl.sh");
    `(cd tmp/testssl.sh;git pull)`;
    is($?,0,"Command executed ok");
} else {
    pass("Cloning testssl.sh");
    `(cd tmp;git clone https://github.com/drwetter/testssl.sh.git)`;
    is($?,0,"Command executed ok");
}

# No script in path
`scanners/testssl.sh/scan -w test -s test --hosts seccubus.com`;
isnt($?,0,"Should fail when path doesn't contain testssl.sh");

# Non-existant path
`scanners/testssl.sh/scan -w test -s test --hosts seccubus.com -p /dev/null/bla`;
isnt($?,0,"Should fail when path doesn't exist");

# No script in path
`scanners/testssl.sh/scan -w test -s test --hosts seccubus.com -p ./testdata`;
isnt($?,0,"Should fail when path doesn't contain testssl.sh");

# Wrong version
my $master = `(cd tmp/testssl.sh;git branch|grep \"*\")`;
$master =~ s/^\* //;
`(cd tmp/testssl.sh;git checkout 2.4)`;
is($?,0,"Command executed ok");
`scanners/testssl.sh/scan -w test -s test --hosts seccubus.com -p ./tmp/testssl.sh`;
isnt($?,0,"Should fail when testssl.is too old");
`scanners/testssl.sh/scan -w test -s test --hosts seccubus.com -p ./tmp/testssl.sh/testssl.sh`;
isnt($?,0,"Should fail when testssl.is too old");
`(cd tmp/testssl.sh;git checkout $master)`;

my $db_version = 0;
foreach my $data_file (glob "db/data_v*.mysql") {
    $data_file =~ /^db\/data_v(\d+)\.mysql$/;
    $db_version = $1 if $1 > $db_version;
}

ok($db_version > 0, "DB version = $db_version");
`mysql -uroot -e "drop database seccubus"`;
`mysql -uroot -e "create database seccubus"`;
`mysql -uroot -e "grant all privileges on seccubus.* to seccubus\@localhost identified by 'seccubus';"`;
`mysql -uroot -e "flush privileges;"`;
`mysql -uroot seccubus < db/structure_v$db_version.mysql`;
`mysql -uroot seccubus < db/data_v$db_version.mysql`;

my $t = Test::Mojo->new('Seccubus');

# Log in
$t->post_ok('/api/session' => { 'REMOTEUSER' => 'admin', "content-type" => "application/json" })
    ->status_is(200,"Login ok")
;

# Create
$t->post_ok('/api/workspaces', json => { 'name' => 'test1'})
    ->status_is(200)
;

my $pwd = `pwd`;
chomp $pwd;

# Create a scan
$t->post_ok('/api/workspace/100/scans',
    json => {
        name          => 'seccubus',
        scanner       => 'testssl.sh',
        parameters    => "-p $pwd/tmp/testssl.sh --hosts \@HOSTS",
        targets       => "www.seccubus.com"
    })
    ->status_is(200)
;


# Lets run scans
pass("Running simple testssl.sh scan");
`bin/do-scan -w test1 -s seccubus`;
is($?,0,"Command executed ok");
# Reactivate Mojo
$t = Test::Mojo->new('Seccubus');

# Log in
$t->post_ok('/api/session' => { 'REMOTEUSER' => 'admin', "content-type" => "application/json" })
    ->status_is(200,"Login ok")
;

# We should have a lot of findings in scan 1
$t->get_ok('/api/workspace/100/findings?Limit=-1&scanIds[]=1')
    ->status_is(200)
    ->json_has("/250", "Should have at least 250 findings in normal scan")
;
foreach my $f ( @{$t->{tx}->res()->json()} ) {
    like($f->{severity}, qr/^[0-3]$/, "Finding $f->{id} has the right priority");
    is($f->{port},"443/tcp","Finnding $f->{id} has the right port");
    like($f->{host},qr/^www\.seccubus\.com\/[\d\:\.]+$/, "Finding $f->{id} has the right hostname");
}

done_testing();
