#!/usr/bin/perl 
#-w
#########################################################
# syncFtp to easily manage vsftpd users 		
# written by Pierluigi Petrelli				
# published at www.petrelli.biz				
#########################################################

#modules used
use DBI;
use Switch;
use File::Copy;
#use Data::Dumper;

###db config
$host     = "localhost";
$database = "vsftpd";
$dbUser   = "vsftpd";
$dbPass   = "dbpass";

#directory contains users settings
$users_conf_dir="/etc/vsftpd/user_conf/";

#directory inside local_root needed to chroot
$def_doc_ins_home = "html";

#if specified this file is copyed inside $def_doc_ins_home
$default_html="/var/www/index.php";

#uid e gid of vsftp, to discover: cat /etc/passwd | grep vsftpd
$folderUid=1000;
$folderGid=65534;

#################### settings end ######################

$dbh = DBI->connect("DBI:mysql:database=$database;host=$host", $dbUser, $dbPass, {RaiseError => 1});


sub recmkdir
{
	print @_;

	my($tpath) = @_;
	my($dir, $accum);

	foreach $dir (split(/\//, $tpath))
	{
    		$accum = "$accum$dir/";
		if($dir ne "")
		{
		      if(! -d "$accum")
		      {
		      		mkdir $accum;
		      }
    		}
  	}
}

sub justFixPerm
{
	my $homeDir      = $_[0];
	my $documentRoot = $homeDir."/".$def_doc_ins_home;
        my @defaultHtmlArray=split(/\//, $default_html);
        my $defaultHtmlFile=$documentRoot."/".$defaultHtmlArray[$#defaultHtmlArray];

	print "Setting right perms on $homeDir...";
	
        chown($folderUid, $folderGid, $homeDir) or print "\nNon posso settare il proprietario su $homeDir $!\n";
        chown($folderUid, $folderGid, $documentRoot) or print "\nNon posso settare il proprietario su $documentRoot $!\n";
        if (-e $default_html) { chown($folderUid, $folderGid, $defaultHtmlFile) or print "\nNon posso settare il proprietario su $defaultHtmlFile $!\n"; }

        chmod(0555, $homeDir) or print "\nNon posso settare i permessi su $homeDir $!\n";
        chmod(0755, $documentRoot) or print "\nNon posso settare i permessi su $documentRoot $!\n";
        if (-e $default_html) { chmod(0755, $defaultHtmlFile) or print "\nNon posso settare i permessi su $defaultHtmlFile $!\n"; }

}


sub createDirFixPerm
{
	my $homeDir = $_[0];
	my $documentRoot= $homeDir."/".$def_doc_ins_home;

	recmkdir($documentRoot, 0555) unless(-d $documentRoot);
		
	opendir(DIR,"$documentRoot");
        my @files = readdir(DIR);  
        closedir(DIR);

	#se dir vuota copio index di default
        if ( ( ($#files+1)-2 == 0 ) && (-e $default_html) )
	{
		copy($default_html,$documentRoot) or print "\nNon riesco a copiare $default_html dentro $documentRoot: $!\n";
	}	

	justFixPerm($homeDir);
}


sub createConfFile
{
	my $user    = $_[0];
	my $homeDir = $_[1];

	open  USRCONF, ">", $users_conf_dir.$user;
        print USRCONF "dirlist_enable=YES\n";
        print USRCONF "download_enable=YES\n";
        print USRCONF "local_root=".$homeDir."\n";
	close USERCONF;

}

sub del
{

	my $user = $_[0];

	print "Deleting $user...";

	#il check è solo sul file, presuppongo che non esista il desync tra file e db, magari è migliorabile
	if ( -e $users_conf_dir.$user ) 
	{
		if (unlink($users_conf_dir.$user) == 0) { print "NON RIESCO A CANCELLARE $user !!!! \n\n"}	
		my $sth = $dbh->prepare("DELETE FROM accounts WHERE username ='$user'");
		$sth->execute();
		print "ok\n";

	}
	else
	{
		print "failed\n";
		print "L'utente $user non ha un account ftp attivo\n";

	}
	
}

sub chUpass
{
	my	$user = $_[0];
	my	$pass = $_[1];

	print "Changing password for $user ... ";
	
	my $sth = $dbh->prepare("UPDATE accounts set pass='$pass' WHERE username='$user'");
	$sth->execute();

	print "ok\n";
}

sub chUdir
{
	my	$user = $_[0];
	my	$homedir = $_[1];

	print "Changing home directory $user ... ";

	my $sth = $dbh->prepare("UPDATE accounts set homedir='$homedir' WHERE username='$user'");
	$sth->execute();

	createConfFile($user,$homedir);
	createDirFixPerm($homedir);

	print "ok\n";
}

sub Ulist
{
	print "Listing $_[0] ...\n";

	my $usrQuery;

	if ($_[0]) 
	{	
		$usrQuery="where username='$_[0]'";
		
	}

	my $sth = $dbh->prepare("SELECT * FROM accounts ".$usrQuery);
	$sth->execute();

	while (my $user = $sth->fetchrow_hashref) 
	{
		print "$user->{username} $user->{pass} $user->{homedir}\n";
	}
}

sub add
{

        my $user = $_[0];
        my $pass = $_[1];
        my $homedir = $_[2];
        my $nocreatedir = $_[3];

        print "Adding $user...";

        if ( -e $users_conf_dir.$user )
        {
                print "L'utente $user è già presente nel database...\n";
                #list($user);
        }
        else
        {
                my $sth = $dbh->prepare("INSERT INTO accounts (username,pass,homedir) VALUES ('$user','$pass','$homedir')");
                $sth->execute();
                createConfFile($user,$homedir);
        }
        if ($nocreatedir ne "nodir")
        {
                createDirFixPerm($homedir);
        }
        print "ok\n";
}

sub sync
{
	print "Syncing...\n";

	#delete all old file
	opendir (CONFFILE, $users_conf_dir);
	@files = readdir (CONFFILE);

	foreach $file (@files) 
	{	
		next if ($file =~ m/^\./);
		print "cancello $users_conf_dir$file\n";
		if (unlink($users_conf_dir.$file) == 0) { print "NON RIESCO A CANCELLARE $FILE !!!! \n\n"}
	}
	closedir (CONFFILE);
	
	##sync per singolo user
	$where=""; 
	$query="SELECT * FROM accounts ".$where;

	my $sth = $dbh->prepare($query);
	$sth->execute();
	while (my $user = $sth->fetchrow_hashref) 
	{
		print "sync per ".$user->{"username"}." ... ";		 
		createConfFile($user->{"username"},$user->{"homedir"});
		createDirFixPerm($user->{"homedir"});
		print "Ok\n";
	}


}

sub help
{ 
	if ($_[0] eq "wrong") 
	{
		print "Wrong parameters usage\n";
	}
	
	print "Usage:\n\nsync (reading from db, it syncs all settings files)\nadd {user} {pass} {homedir} [optional:nodir]\ndel {user}\nlist {user (not mandatory)}\nchdir {user} {homedir}\nchpass {user} {pass}\n\n"; 
	print "syncFtp is written by Pierluigi Petrelli\nEmail pierluigi\@neuron-webagency.com\nblog www.petrelli.biz\nFeel free to contact him\n";
}



switch ($ARGV[0])
{
	case 'sync'   { sync(); }
        case 'add'    { if ( $ARGV[1] && $ARGV[2] && $ARGV[3] ) { add($ARGV[1],$ARGV[2],$ARGV[3],$ARGV[4]); } else { help('wrong');} }
        case 'del'    { if ( $ARGV[1] ) { del($ARGV[1]); } else { help('wrong');}  }
        case 'list'   { Ulist($ARGV[1]); }	
        case 'send'   { }	
        case 'chdir'  { if ( $ARGV[1] && $ARGV[2] ) { chUdir($ARGV[1],$ARGV[2]); } else { help('wrong');}  }	
        case 'chpass' { if ( $ARGV[1] && $ARGV[2] ) { chUpass($ARGV[1],$ARGV[2]); } else { help('wrong');} }	
        else          { help(); }
	
}









