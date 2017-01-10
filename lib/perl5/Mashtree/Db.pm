#!/usr/bin/env perl
package Mashtree::Db;
use strict;
use warnings;
use Exporter qw(import);
use File::Basename qw/fileparse basename dirname/;
use Data::Dumper;
use DBI;

use lib dirname($INC{"Mashtree/Db.pm"});
use lib dirname($INC{"Mashtree/Db.pm"})."/..";

use Mashtree qw/_truncateFilename logmsg sortNames/;


our @EXPORT_OK = qw(
         );

local $0=basename $0;

# Properties of this object:
#   dbFile
#   dbh
sub new{
  my($class,$dbFile,$settings)=@_;

  my $self={};
  bless($self,$class);

  $self->selectDb($dbFile);
  return $self;
}

# Create an SQLite database for genome distances.
sub selectDb{
  my($self, $dbFile)=@_;

  $self->{dbFile}=$dbFile;

  $self->connect();

  if(-e $dbFile && -s $dbFile > 0){
    return 0;
  }

  my $dbh=$self->{dbh};
  $dbh->do(qq(
    CREATE TABLE DISTANCE(
      GENOME1     CHAR(255)    NOT NULL,
      GENOME2     CHAR(255)    NOT NULL,
      DISTANCE    INT          NOT NULL,
      PRIMARY KEY(GENOME1,GENOME2)
    )) 
  );

  return 1;
}

sub connect{
  my($self)=@_;

  my $dbFile=$self->{dbFile};
  my $dbh=DBI->connect("dbi:SQLite:dbname=$dbFile","","",{
      RaiseError => 1
  });
  
  $self->{dbh}=$dbh;
  
  return $dbh;
}

sub addDistances{
  my($self,$distancesFile)=@_;

  my $dbh=$self->{dbh};

  open(my $fh, "<", $distancesFile) or die "ERROR: could not read $distancesFile: $!";
  my $query="";
  while(<$fh>){
    chomp;
    if(/^#\s*query\s+(.+)/){
      $query=$1;
      $query=~s/^\s+|\s+$//g;  # whitespace trim before right-padding is added
      $query=_truncateFilename($query);
      next;
    }
    my($subject,$distance)=split(/\t/,$_);
    $subject=~s/^\s+|\s+$//g;  # whitespace trim before right-padding is added
    $subject=_truncateFilename($subject);
    
    next if(defined($self->findDistance($query,$subject)));

    $dbh->do(qq(
      INSERT INTO DISTANCE VALUES("$query", "$subject", $distance);
    ));
    
    if($dbh->err()){
      die "ERROR: could not insert $query,$subject,$distance into the database:\n  ".$dbh->err();
    }
  }
}

sub findDistance{
  my($self,$genome1,$genome2)=@_;

  my $dbh=$self->{dbh};
  
  my $sth=$dbh->prepare(qq(SELECT DISTANCE FROM DISTANCE WHERE GENOME1="$genome1" AND GENOME2="$genome2"));
  my $rv = $sth->execute() or die $DBI::errstr;
  if($rv < 0){
    die $DBI::errstr;
  }

  # Distance will be undefined unless there is a result
  # on the SQL select statement.
  my $distance;
  while(my @row=$sth->fetchrow_array()){
    ($distance)=@row;
  }
  return $distance;
}

# Format can be:
#   tsv    3-column format
#   phylip Phylip matrix format
sub toString{
  my($self,$format)=@_;
  $format//="tsv";
  $format=lc($format);
  
  if($format eq "tsv"){
    return $self->toString_tsv();
  } elsif($format eq "phylip"){
    return $self->toString_phylip();
  }

  die "ERROR: could not format ".ref($self)." as $format.";
}

sub toString_tsv{
  my($self)=@_;
  my $dbh=$self->{dbh};

  my $str="";
  
  my $sth=$dbh->prepare(qq(
    SELECT GENOME1,GENOME2,DISTANCE
    FROM DISTANCE
    ORDER BY GENOME1,GENOME2 ASC
  ));
  my $rv=$sth->execute or die $DBI::errstr;
  if($rv < 0){
    die $DBI::errstr;
  }

  while(my @row=$sth->fetchrow_array()){
    $str.=join("\t",@row)."\n";
  }
  return $str;
}

sub toString_phylip{
  my($self)=@_;
  my $dbh=$self->{dbh};

  my $str="";

  # The way phylip is, I need to know the genome names
  # a priori
  my @name;
  my $sth=$dbh->prepare(qq(
    SELECT DISTINCT(GENOME1) 
    FROM DISTANCE 
    ORDER BY GENOME1 ASC
  ));
  my $rv=$sth->execute or die $DBI::errstr;
  if($rv < 0){
    die $DBI::errstr;
  }

  my $maxGenomeLength=0;
  while(my @row=$sth->fetchrow_array()){
    push(@name,$row[0]);
    $maxGenomeLength=length($row[0]) if(length($row[0]) > $maxGenomeLength);
  }

  my $numGenomes=@name;

  $str.=(" " x 4) . "$numGenomes\n";
  for(my $i=0;$i<$numGenomes;$i++){
    $str.=$name[$i];
    $str.=" " x ($maxGenomeLength - length($name[$i]) + 2);
    for(my $j=0;$j<$numGenomes;$j++){
      $str.=sprintf("%0.4f  ",$self->findDistance($name[$i],$name[$j]));
    }
    $str=~s/ +$/\n/; # replace that trailing whitespace with a newline
  }
  return $str;
}

1; # gotta love how we we return 1 in modules. TRUTH!!!

