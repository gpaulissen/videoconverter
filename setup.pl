#!/usr/bin/env perl

=pod

=head1 NAME

setup.pl - Setup the environment for this Node.js project

=head1 SYNOPSIS

  setup.pl [OPTION...]

=head1 DESCRIPTION

This script will:

=over 4

=item setup the backend directory

=item setup the frontend directory

=back

=head1 OPTIONS

=over 4

=item B<--help>

This help.

=item B<--init>

Recreate the project, i.e. remove the backend and frontend directories first.

=item B<--verbose>

Increase verbose logging. Defaults to environment variable VERBOSE if set to a number, otherwise 0.

=back

=head1 NOTES

=head1 EXAMPLES

=head1 BUGS

=head1 SEE ALSO

=head1 AUTHOR

Gert-Jan Paulissen, E<lt>gert.jan.paulissen@gmail.com<gt>.

=head1 VERSION

$Header$

=head1 HISTORY

21-04-2021  G.J. Paulissen

First version.

=cut

use autodie qw(open close);
use English qw( -no_match_vars ) ; 
use Cwd qw(abs_path getcwd);
use File::Basename;
use File::Copy;
use File::Find::Rule;
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw/ :POSIX /;
use File::Touch;
use File::Which;
use File::chdir;
use Getopt::Long;
use Pod::Usage;
use warnings;
use Carp qw(croak);
use Test::More; # do not know how many in advance
use Data::Dumper;
use Storable qw(retrieve store);

# VARIABLES

my $program = &basename($PROGRAM_NAME);

my $verbose = ( exists($ENV{VERBOSE}) && $ENV{VERBOSE} =~ m/^\d+$/o ? $ENV{VERBOSE} : 0 );

my $install_msg = "Please install the tools ";

# PROTOTYPES

sub main ();
sub process_command_line ();
sub check_environment ();
sub check_os ();
sub check_npm ();
sub setup_backend ();
sub setup_frontend ();
sub execute ($$$);
sub check_status ($$);
sub cmd ($@);
sub update_file ($$$;$);
sub debug (@);

# MAIN

main();

# SUBROUTINES

sub main () {
    delete($ENV{'HTTP_PROXY'}) if (exists($ENV{'HTTP_PROXY'}));
    delete($ENV{'HTTPS_PROXY'}) if (exists($ENV{'HTTPS_PROXY'}));
    
    process_command_line();
    check_environment();
    setup_backend();
    setup_frontend();

    done_testing();   # reached the end safely
}

sub process_command_line ()
{
    # Windows FTYPE and ASSOC cause the command '<program> -h -c file'
    # to have ARGV[0] == ' -h -c file' and number of arguments 1.
    # Hence strip the spaces from $ARGV[0] and recreate @ARGV.
    if ( @ARGV == 1 && $ARGV[0] =~ s/^\s+//o ) {
        @ARGV = split( / /, $ARGV[0] );
    }

    Getopt::Long::Configure(qw(require_order));

    #
    GetOptions('help' => sub { pod2usage(-verbose => 2) },
               'init' => sub { remove_tree('backend', 'frontend', { verbose => 0, safe => 1 }) },
               'verbose+' => \$verbose
        )
        or pod2usage(-verbose => 0);
}

sub check_environment () {
    BAIL_OUT("Please use Windows Perl or Mac OS Perl or linux")
        unless ok($^O =~ m/^(MSWin32|darwin|linux)$/, "Perl build operating system ($^O) must be 'MSWin32' or 'darwin' or 'linux'");

    check_os();
    check_npm();
}

sub check_os () {
    if ($^O eq 'MSWin32') {
      SKIP: {
          my $tests = 1; # number of tests in this block

          # if where can not be found on the PATH, the command 'svn --version 2>&1' later on will give an error
          skip "!!! IMPORTANT !!! Please add " . $ENV{'SystemRoot'} . "\\System32 to the PATH ($install_msg)", ($tests-1)
              unless (ok(defined(which('where')), "The program where must be found in the PATH"));
        }
    }
}

sub check_npm () {
  SKIP: {
      my $min_version = '6.13.4';
      my $prog = 'npm';
      my $tests = 3; # number of tests in this block

      skip "!!! IMPORTANT !!! Please install ($prog) $min_version or higher ($install_msg)", ($tests-1)
          unless (ok(defined(which($prog)), "Node.js package manager ($prog) must be found in the PATH"));

      # $ npm -version
      # returns
      # 6.13.4

      my @stdout;
      my @cmd = ($prog, '-version');

      eval {
          execute(\@stdout, \@stdout, \@cmd);
      };
      BAIL_OUT("Can not run '@cmd': $@")
          if ($@);

      my $line = ($#stdout >= 0 ? $stdout[0] : '');

      diag("Just read line $line")
          if ($verbose >= 1);

      $line =~ m/(\S+)/;

      my $version = $1;

      ok(defined($version), "'@cmd' version line contains version '$version'");

      ok(version->parse($version) >= version->parse($min_version), "$prog version ($version) must be at least '$min_version'");
    }
}

sub setup_backend () {
    my $dir = 'backend';    
    my $cache_file = File::Spec->rel2abs('.' . $dir);
    my %cache = ();
    my $r_cache = \%cache;

    # beware of removing cache if the directory is not there (anymore)
    unlink($cache_file)
        if (-f $cache_file && ! -d $dir);

    if (-f $cache_file) {
        $r_cache = retrieve($cache_file);
    }
    
    mkdir($dir)
        unless -d $dir;

    eval {
    
      SKIP: {
          local $CWD = $dir;

          ok(getcwd() =~ m/$dir$/, "Now in $dir directory");

          cmd($r_cache, 'npx', 'express-generator');
          cmd($r_cache, 'npm', 'install');
          cmd($r_cache, 'npm', 'i', '@babel/cli', '@babel/core', '@babel/node', '@babel/preset-env', 'bull', 'cors', 'dotenv', 'fluent-ffmpeg', 'ffprobe-static', 'multer' , 'sequelize', 'sqlite3');

          update_file($r_cache, '.', '.babelrc');

          my $file = File::Spec->catfile('.', 'package.json');
          
          if (!exists($r_cache->{'file'}{$file})) {
              my $fh = IO::File->new($file, "r");
              my @lines = <$fh>;

              for my $i (0 .. $#lines) {
                  if ($lines[$i] =~ m!^    "start": "node ./bin/www"$!) {
                      $lines[$i] = <<'END';
    "start": "nodemon --exec npm run babel-node --  ./bin/www",
    "babel-node": "babel-node"
END
                  }
              }

              $fh = IO::File->new($file, "w");
              
              print $fh join('', @lines);

              $fh->close();
              $r_cache->{'file'}{$file} = 1;
          }

          cmd($r_cache, 'npm', 'install', '--save-dev', 'sequelize-cli');
          cmd($r_cache, 'npx', 'sequelize', 'init');

          update_file($r_cache, 'config', 'config.json');

          cmd($r_cache, 'npx', 'sequelize-cli', '--name', 'VideoConversion', '--attributes', 'filePath:string,convertedFilePath:string,outputFormat:string,status:enum', 'model:generate');

          # find the migration script
          my @files = File::Find::Rule->file()->name('*-create-video-conversion.js')->in('migrations');

          ok(@files == 1, "File '$files[0]' found");

          update_file($r_cache, 'migrations', basename($files[0]), 'create-video-conversion.js');
          
          update_file($r_cache, 'models', 'videoconversion.js');

          # create the database
          cmd($r_cache, 'npx', 'sequelize-cli', 'db:migrate');
          
          create_directory($r_cache, 'files');
          create_directory($r_cache, 'queues');

          update_file($r_cache, 'queues', 'videoQueue.js');

          if ($^O eq 'linux') {
              cmd($r_cache, 'sudo', 'apt-get', 'update');
              cmd($r_cache, 'sudo', 'apt-get', 'upgrade');
              cmd($r_cache, 'sudo', 'apt-get', 'install', 'redis-server');
              cmd($r_cache, 'redis-server');
          }

          update_file($r_cache, 'routes', 'conversions.js');

          update_file($r_cache, '.', 'app.js');

          $file = File::Spec->catfile('.', '.env');
          
          if (!exists($r_cache->{'file'}{$file})) {          
              if (! -f $file) {
                  my $root = ($^O eq 'MSWin32' ? $ENV{'USERPROFILE'} : '/');
                  my $ext = ($^O eq 'MSWin32' ? '.exe' : '');

                  my @ffmpeg = File::Find::Rule->file()->name("ffmpeg$ext")->in($root);
                  my @ffprobe = File::Find::Rule->file()->name("ffprobe$ext")->in('node_modules'); # ffprobe-static installs here

                  print STDERR "@ffmpeg\n";
                  print STDERR "@ffprobe\n";
                  
                  ok(@ffmpeg > 0, "Executable ffmpeg found");
                  ok(@ffprobe > 0, "Executable ffprobe found");

                  my $ffmpeg = File::Spec->canonpath($ffmpeg[$#ffmpeg]);
                  my $ffprobe = File::Spec->canonpath($ffprobe[$#ffprobe]); # use latest since on Windows there is a ia32 and x64 variant

                  my $fh = IO::File->new($file, "w");
                  
                  print $fh <<"END";
FFMPEG_PATH='$ffmpeg'
FFPROBE_PATH='$ffprobe'
END

                  $fh->close();
              }
              $r_cache->{'file'}{$file} = 1;              
          }
          ok(-f $file, "File '$file' exists");
        }
    };
    
    store($r_cache, $cache_file);

    die $@
        if $@;
}

sub setup_frontend () {
    my $dir = 'frontend';
    my $cache_file = File::Spec->rel2abs('.' . $dir);
    my %cache = ();
    my $r_cache = \%cache;

    # beware of removing cache if the directory is not there (anymore)
    unlink($cache_file)
        if (-f $cache_file && ! -d $dir);

    if (-f $cache_file) {
        $r_cache = retrieve($cache_file);
    }

    eval {
    
        if (! -d $dir) {
            cmd($r_cache, 'npx', 'create-react-app', 'frontend');
        }
        
      SKIP: {
          local $CWD = $dir;

          ok(getcwd() =~ m/$dir$/, "Now in $dir directory");

          cmd($r_cache, 'npm', 'i', 'axios', 'bootstrap', 'formik', 'mobx', 'mobx-react', 'react-bootstrap', 'react-router-dom');

          update_file($r_cache, 'src', 'App.js');

          update_file($r_cache, 'src', 'App.css');

          update_file($r_cache, 'src', 'HomePage.js');

          update_file($r_cache, 'src', 'request.js');
          
          update_file($r_cache, 'src', 'store.js');

          update_file($r_cache, 'src', 'TopBar.js');

          update_file($r_cache, 'public', 'index.html');

          cmd($r_cache, 'npm', 'i', '-g', 'nodemon');
        }
    };
    
    store($r_cache, $cache_file);

    die $@
        if $@;
}

sub execute ($$$) {
    my ($r_stdout, $r_stderr, $cmd) = @_;

    my $process = (ref($cmd) eq 'ARRAY' ? "@$cmd": $cmd);

    my ($fh, $stdout, $stderr);

    if (defined($r_stdout)) {
        $stdout = tmpnam();
        $process .= " 1>$stdout";
    }
    if (defined($r_stderr)) {
        $stderr = tmpnam();
        $process .= " 2>$stderr";
    }
    
    eval {
        system($process);
    };
    
    if (defined($r_stdout)) {
        $fh = IO::File->new($stdout, "r");
        push(@$r_stdout, <$fh>);
        $fh->close();
        unlink($stdout);
    }
    if (defined($r_stderr)) {
        $fh = IO::File->new($stderr, "r");
        push(@$r_stderr, <$fh>);
        $fh->close();
        unlink($stderr);
    }
    
    die "$process\n$@" if $@;
    check_status($process, $?);
}

sub check_status ($$) {
    my ($process, $status) = @_;

    if (defined($status)) {
        if ($status == -1) {
            die "$process\nFailed to execute: $!";
        }
        elsif ($status & 127) {
            die sprintf("$process\nChild died with signal %d, %s coredump", ($status & 127),  ($status & 128) ? 'with' : 'without');
        }
        elsif (($status >> 8) != 0) {
            die sprintf("$process\nChild exited with value %d", $status >> 8);
        }
    }
}

sub cmd ($@) {
    my ($r_cache, @cmd) = @_;
        
    if (!exists($r_cache->{'cmd'}{"@cmd"})) {
        eval {
            execute(undef, undef, \@cmd);
        };
        BAIL_OUT("Can not run '@cmd': $@")
            if ($@);
        $r_cache->{'cmd'}{"@cmd"} = 1;
    }
    ok(1, "Command '@cmd' executed");
}

sub update_file ($$$;$) {
    my $r_cache = shift @_;
    my ($dir, $dst_basename, $tpl_basename) = @_;
    my $current_dir = basename(getcwd());
    my $tpl_file = File::Spec->catfile('..', 'tpl', $current_dir, $dir, (defined($tpl_basename) ? $tpl_basename : $dst_basename));
    my $dst_file = File::Spec->catfile($dir, $dst_basename);

    die "Template file ($tpl_file) does not exist"
        unless -f $tpl_file;
    
    # cache does not exists or destination does not exist or older than template?
    if (!exists($r_cache->{'file'}{$dst_file}) ||
        ! -f $dst_file ||
        (stat($dst_file))[9] < (stat($tpl_file))[9]) {
        copy($tpl_file, $dst_file);
        $r_cache->{'file'}{$dst_file} = 1;
    }
    ok(-f $dst_file, "File '$dst_file' created");
}      

sub create_directory ($$) {
    my ($r_cache, $dir) = @_;

    if (!(exists($r_cache->{'dir'}{$dir}) && -d $dir)) {
        mkdir($dir)
            unless -d $dir;
        $r_cache->{'dir'}{$dir} = 1;
    }
    ok(-d $dir, "Directory '$dir' exists");
}


sub debug (@) {
    print STDERR "@_\n"
        if $verbose > 0;
}




