#!/usr/bin/perl -w
#
# Backup all MySQL Databases to Amazon S3
#
# Author: David Parrish <david@dparrish.com>
#
# WARNING:
#   You must have an Amazon S3 account
#   You must install the Amazon::S3 perl module
#
#
# Configure this stuff:
#
my $aws_access_key_id     = "your access key goes here";
my $aws_secret_access_key = "your secret key goes here";

# Enter a username & password that have the appropriate permissions to backup
# all databases
my $mysql_username = "root";
my $mysql_password = "mysql password here";
my $mysql_hostname = "localhost";

# Add any database names you don't want backed up to here
my @mysql_skip_databases = qw( skip_this_db and_another );

# You probably don't need to change this. It makes up a sane name for the
# bucket (directory) that the backup files will be stored in
my $bucket_name = $aws_access_key_id. '-mysql-$hostname';


# You should only need to change these if mysqldump complains about something
my @mysqldump_options = qw(
  --add-locks
  --comments
  --delayed-insert
  --disable-keys
  --extended-insert 
  --quick
  --quote-names
  --result-file=foo
);




#########################################
#        Configuration Ends Here        #
#########################################

use strict;
use Amazon::S3;
use Sys::Hostname;
use File::Temp qw/ tmpnam /;
use DBI;
use Data::Dumper;

my $s3 = new Amazon::S3 {
  aws_access_key_id     => $aws_access_key_id,
  aws_secret_access_key => $aws_secret_access_key
};

my $dbh = DBI->connect("DBI:mysql:database=mysql;host=$mysql_hostname",
  $mysql_username, $mysql_password, { RaiseError => 1 });

# Create a bucket
$bucket_name =~ s/\$hostname/hostname()/e;
my $bucket = $s3->add_bucket({ bucket => $bucket_name })
  or die $s3->err. ": " . $s3->errstr;

my $sth = $dbh->prepare("SHOW DATABASES");
$sth->execute;
while (my $row = $sth->fetchrow_hashref)
{
  next unless $row->{Database};
  next if grep { $_ eq $row->{Database} } @mysql_skip_databases;
  my $filename = tmpnam();
  system("/usr/bin/mysqldump", @mysqldump_options,
    "-u", $mysql_username, "-p$mysql_password",
    "-h", $mysql_hostname,
    "-r", $filename,
    $row->{Database});
  if (-f $filename && -s _ > 1 && open(FH, "<$filename"))
  {
    my $text = join("", <FH>);
    close(FH);
    if (!$bucket->add_key("$row->{Database}.sql", $text, { content_type => 'text/sql' }))
    {
      print "Error saving backup for $row->{Database}: ". $s3->err. ": ". $s3->errstr. "\n";
    }
    else
    {
      print "Backed up $row->{Database} (". length($text). " bytes)\n";
    }
  }
  else
  {
    print "Error dumping database $row->{Database}\n";
  }
  unlink($filename);
}

