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
    
    mkdir($dir)
        unless -d $dir;
    
  SKIP: {
      my $test_nr = 1;
      local $CWD = $dir;

      my $ok = sub { my ($result, $msg) = @_; ok($result, $msg); };
      
      ok(getcwd() =~ m/$dir$/, "Now in $dir directory");

      my $cmd = sub {
          my @cmd = @_;
          
          if (! -f ".$test_nr") {
              eval {
                  execute(undef, undef, \@cmd);
              };
              BAIL_OUT("Can not run '@cmd': $@")
                  if ($@);
              touch("." . $test_nr++);
          }
          $ok->(1, "Command '@cmd' executed");
      };

      $cmd->('npx', 'express-generator');
      $cmd->('npm', 'install');
      $cmd->('npm', 'i', '@babel/cli', '@babel/core', '@babel/node', '@babel/preset-env', 'bull', 'cors', 'dotenv', 'fluent-ffmpeg', 'ffprobe-static', 'multer' , 'sequelize', 'sqlite3');

      my $write = sub {
          my ($file, $str) = @_;

          debug("write '$file' in '" . getcwd() . "'");
          
          if (! -f $file) {
              my $fh = IO::File->new($file, "w");
      
              print $fh $str;

              $fh->close();
          }
          $ok->(-f $file, "File '$file' created");
      };

      $write->('.babelrc', <<'END');
{
    "presets": [
        "@babel/preset-env"
    ]
}
END

      if (! -f ".$test_nr") {
          my $file = 'package.json';
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
          
          $write->($file, join('', @lines));
          touch("." . $test_nr++);
      }

      $cmd->('npm', 'install', '--save-dev', 'sequelize-cli');
      $cmd->('npx', 'sequelize', 'init');

      $write->(File::Spec->catfile('config', 'config.json'), <<'END');
{
  "development": {
    "dialect": "sqlite",
    "storage": "development.db"
  },
  "test": {
    "dialect": "sqlite",
    "storage": "test.db"
  },
  "production": {
    "dialect": "sqlite",
    "storage": "production.db"
  }
}
END

      $cmd->('npx', 'sequelize-cli', '--name', 'VideoConversion', '--attributes', 'filePath:string,convertedFilePath:string,outputFormat:string,status:enum', 'model:generate');

      # find the migration script
      my @files = File::Find::Rule->file()->name('*-create-video-conversion.js')->in('migrations');

      $ok->(@files == 1, "File '$files[0]' found");

      $write->($files[0], <<'END');      
"use strict";
module.exports = {
  up: (queryInterface, Sequelize) => {
    return queryInterface.createTable("VideoConversions", {
      id: {
        allowNull: false,
        autoIncrement: true,
        primaryKey: true,
        type: Sequelize.INTEGER
      },
      filePath: {
        type: Sequelize.STRING
      },
      convertedFilePath: {
        type: Sequelize.STRING
      },
      outputFormat: {
        type: Sequelize.STRING
      },
      status: {
        type: Sequelize.ENUM,
        values: ["pending", "done", "cancelled"],
        defaultValue: "pending"
      },
      createdAt: {
        allowNull: false,
        type: Sequelize.DATE
      },
      updatedAt: {
        allowNull: false,
        type: Sequelize.DATE
      }
    });
  },
  down: (queryInterface, Sequelize) => {
    return queryInterface.dropTable("VideoConversions");
  }
};
END
      
      $write->(File::Spec->catfile('models', 'videoconversion.js'), <<'END');
"use strict";
module.exports = (sequelize, DataTypes) => {
  const VideoConversion = sequelize.define(
    "VideoConversion",
    {
      filePath: DataTypes.STRING,
      convertedFilePath: DataTypes.STRING,
      outputFormat: DataTypes.STRING,
      status: {
        type: DataTypes.ENUM("pending", "done", "cancelled"),
        defaultValue: "pending"
      }
    },
    {}
  );
  VideoConversion.associate = function(models) {
    // associations can be defined here
  };
  return VideoConversion;
};
END

      # create the database
      $cmd->('npx', 'sequelize-cli', 'db:migrate');
      
      my $dir = sub { my ($dir) = @_; mkdir($dir) unless -d $dir; $ok->(-d $dir, "Directory '$dir' exists"); };

      $dir->('files');
      $dir->('queues');

      $write->(File::Spec->catfile('queues', 'videoQueue.js'), <<'END');
const Queue = require("bull");
const videoQueue = new Queue("video transcoding");
const models = require("../models");
var ffmpeg = require("fluent-ffmpeg");
const fs = require("fs");
const convertVideo = (path, format) => {
  const fileName = path.replace(/\.[^/.]+$/, "");
  const convertedFilePath = `${fileName}_${+new Date()}.${format}`;
  return new Promise((resolve, reject) => {
    ffmpeg(`${__dirname}/../files/${path}`)
      .setFfmpegPath(process.env.FFMPEG_PATH)
      .setFfprobePath(process.env.FFPROBE_PATH)
      .toFormat(format)
      .on("start", commandLine => {
        console.log(`Spawned Ffmpeg with command: ${commandLine}`);
      })
      .on("error", (err, stdout, stderr) => {
        console.log(err, stdout, stderr);
        reject(err);
      })
      .on("end", (stdout, stderr) => {
        console.log(stdout, stderr);
        resolve({ convertedFilePath });
      })
      .saveToFile(`${__dirname}/../files/${convertedFilePath}`);
  });
};
videoQueue.process(async job => {
  const { id, path, outputFormat } = job.data;
  try {
    const conversions = await models.VideoConversion.findAll({ where: { id } });
    const conv = conversions[0];
    if (conv.status == "cancelled") {
      return Promise.resolve();
    }
    const pathObj = await convertVideo(path, outputFormat);
    const convertedFilePath = pathObj.convertedFilePath;
    const conversion = await models.VideoConversion.update(
      { convertedFilePath, status: "done" },
      {
        where: { id }
      }
    );
    Promise.resolve(conversion);
  } catch (error) {
    Promise.reject(error);
  }
});
export { videoQueue };
END

      if ($^O eq 'linux') {
          $cmd->('sudo', 'apt-get', 'update');
          $cmd->('sudo', 'apt-get', 'upgrade');
          $cmd->('sudo', 'apt-get', 'install', 'redis-server');
          $cmd->('redis-server');
      }

      $write->(File::Spec->catfile('routes', 'conversions.js'), <<'END');
var express = require("express");
var router = express.Router();
const models = require("../models");
var multer = require("multer");
const fs = require("fs").promises;
const path = require("path");
import { videoQueue } from "../queues/videoQueue";
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, "./files");
  },
  filename: (req, file, cb) => {
    cb(null, `${+new Date()}_${file.originalname}`);
  }
});
const upload = multer({ storage });
router.get("/", async (req, res, next) => {
  const conversions = await models.VideoConversion.findAll();
  res.json(conversions);
});
router.post("/", upload.single("video"), async (req, res, next) => {
  const data = { ...req.body, filePath: req.file.path };
  const conversion = await models.VideoConversion.create(data);
  res.json(conversion);
});
router.delete("/:id", async (req, res, next) => {
  const id = req.params.id;
  const conversions = await models.VideoConversion.findAll({ where: { id } });
  const conversion = conversions[0];
  try {
    await fs.unlink(`${__dirname}/../${conversion.filePath}`);
    if (conversion.convertedFilePath) {
      await fs.unlink(`${__dirname}/../files/${conversion.convertedFilePath}`);
    }
  } catch (error) {
  } finally {
    await models.VideoConversion.destroy({ where: { id } });
    res.json({});
  }
});
router.put("/cancel/:id", async (req, res, next) => {
  const id = req.params.id;
  const conversion = await models.VideoConversion.update(
    { status: "cancelled" },
    {
      where: { id }
    }
  );
  res.json(conversion);
});
router.get("/start/:id", async (req, res, next) => {
  const id = req.params.id;
  const conversions = await models.VideoConversion.findAll({ where: { id } });
  const conversion = conversions[0];
  const outputFormat = conversion.outputFormat;
  const filePath = path.basename(conversion.filePath);
  await videoQueue.add({ id, path: filePath, outputFormat });
  res.json({});
});
module.exports = router;
END

      $write->('app.js', <<'END');
require("dotenv").config();
var createError = require("http-errors");
var express = require("express");
var path = require("path");
var cookieParser = require("cookie-parser");
var logger = require("morgan");
var cors = require("cors");
var indexRouter = require("./routes/index");
var conversionsRouter = require("./routes/conversions");
var app = express();
// view engine setup
app.set("views", path.join(__dirname, "views"));
app.set("view engine", "jade");
app.use(logger("dev"));
app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, "public")));
app.use(express.static(path.join(__dirname, "files")));
app.use(cors());
app.use("/", indexRouter);
app.use("/conversions", conversionsRouter);
// catch 404 and forward to error handler
app.use(function(req, res, next) {
  next(createError(404));
});
// error handler
app.use(function(err, req, res, next) {
  // set locals, only providing error in development
  res.locals.message = err.message;
  res.locals.error = req.app.get("env") === "development" ? err : {};
// render the error page
  res.status(err.status || 500);
  res.render("error");
});
module.exports = app;
END

      if (! -f ".env") {
          my $root = ($^O eq 'MSWin32' ? $ENV{'USERPROFILE'} : '/');
          my $ext = ($^O eq 'MSWin32' ? '.exe' : '');

          my @ffmpeg = File::Find::Rule->file()->name("ffmpeg$ext")->in($root);
          my @ffprobe = File::Find::Rule->file()->name("ffprobe$ext")->in('node_modules'); # ffprobe-static installs here

          print STDERR "@ffmpeg\n";
          print STDERR "@ffprobe\n";
          
          $ok->(@ffmpeg > 0, "Executable ffmpeg found");
          $ok->(@ffprobe > 0, "Executable ffprobe found");

          my $ffmpeg = File::Spec->canonpath($ffmpeg[$#ffmpeg]);
          my $ffprobe = File::Spec->canonpath($ffprobe[$#ffprobe]); # use latest since on Windows there is a ia32 and x64 variant

          $write->('.env', <<"END");
FFMPEG_PATH='$ffmpeg'
FFPROBE_PATH='$ffprobe'
END
      }
      $ok->(-f ".env", "File '.env' exists");
    }
}

sub setup_frontend () {
    my $dir = 'frontend';

    my $test_nr = 1; # number of tests in this block
    
    my $ok = sub { my ($result, $msg) = @_; ok($result, $msg); };
    
    my $cmd = sub {
        my @cmd = @_;
        
        if (! -f ".$test_nr") {
            eval {
                execute(undef, undef, \@cmd);
            };
            BAIL_OUT("Can not run '@cmd': $@")
                if ($@);
            touch("." . $test_nr++);
        }
        $ok->(1, "Command '@cmd' executed");
    };

    if (! -d $dir) {
        $cmd->('npx', 'create-react-app', 'frontend');
    }
        
  SKIP: {
      local $CWD = $dir;

      ok(getcwd() =~ m/$dir$/, "Now in $dir directory");

      $cmd->('npm', 'i', 'axios', 'bootstrap', 'formik', 'mobx', 'mobx-react', 'react-bootstrap', 'react-router-dom');

      my $write = sub {
          my ($file, $str) = @_;
          
          if (! -f $file) {
              my $fh = IO::File->new($file, "w");
      
              print $fh $str;

              $fh->close();
          }
          $ok->(-f $file, "File '$file' created");
      };
      
      $write->(File::Spec->catfile('src', 'App.js'), <<'END');
import React from "react";
import { Router, Route } from "react-router-dom";
import "./App.css";
import { createBrowserHistory as createHistory } from "history";
import HomePage from "./HomePage";
import { ConversionsStore } from "./store";
import TopBar from "./TopBar";
const conversionsStore = new ConversionsStore();
const history = createHistory();
function App() {
  return (
    <div className="App">
      <TopBar />
      <Router history={history}>
        <Route
          path="/"
          exact
          component={props => (
            <HomePage {...props} conversionsStore={conversionsStore} />
          )}
        />
      </Router>
    </div>
  );
}
export default App;
END

      $write->(File::Spec->catfile('src', 'App.css'), <<'END');
.page {
  padding: 20px;
}
.button {
  margin-right: 10px;
}
END

      $write->(File::Spec->catfile('src', 'HomePage.js'), <<'END');
import React, { useCallback } from "react";
import Table from "react-bootstrap/Table";
import Button from "react-bootstrap/Button";
import ButtonToolbar from "react-bootstrap/ButtonToolbar";
import { observer } from "mobx-react";
import {
  getJobs,
  addJob,
  deleteJob,
  cancel,
  startJob,
  APIURL
} from "./request";
import { Formik } from "formik";
import Form from "react-bootstrap/Form";
import Col from "react-bootstrap/Col";
function HomePage({ conversionsStore }) {
  const fileRef = React.createRef();
  const [file, setFile] = React.useState(null);
  const [fileName, setFileName] = React.useState("");
  const [initialized, setInitialized] = React.useState(false);
  const onChange = event => {
    setFile(event.target.files[0]);
    setFileName(event.target.files[0].name);
  };
  const openFileDialog = () => {
    fileRef.current.click();
  };
  const handleSubmit = async evt => {
    if (!file) {
      return;
    }
    let bodyFormData = new FormData();
    bodyFormData.set("outputFormat", evt.outputFormat);
    bodyFormData.append("video", file);
    await addJob(bodyFormData);
    getConversionJobs();
  };
  const getConversionJobs = async () => {
    const response = await getJobs();
    conversionsStore.setConversions(response.data);
  };
  const getConversionJobsCB = useCallback(() => {
    getConversionJobs();
  });
  const deleteConversionJob = async id => {
    await deleteJob(id);
    getConversionJobs();
  };
  const cancelConversionJob = async id => {
    await cancel(id);
    getConversionJobs();
  };
  const startConversionJob = async id => {
    await startJob(id);
    getConversionJobs();
  };
  React.useEffect(() => {
    if (!initialized) {
      getConversionJobs();
      setInitialized(true);
    }
  }, [initialized, getConversionJobsCB, getConversionJobs]);
  return (
    <div className="page">
      <h1 className="text-center">Convert Video</h1>
      <Formik onSubmit={handleSubmit} initialValues={{ outputFormat: "mp4" }}>
        {({
          handleSubmit,
          handleChange,
          handleBlur,
          values,
          touched,
          isInvalid,
          errors
        }) => (
          <Form noValidate onSubmit={handleSubmit}>
            <Form.Row>
              <Form.Group
                as={Col}
                md="12"
                controlId="outputFormat"
                defaultValue="mp4"
              >
                <Form.Label>Output Format</Form.Label>
                <Form.Control
                  as="select"
                  value={values.outputFormat || "mp4"}
                  onChange={handleChange}
                  isInvalid={touched.outputFormat && errors.outputFormat}
                >
                  <option value="mov">mov</option>
                  <option value="webm">webm</option>
                  <option value="mp4">mp4</option>
                  <option value="mpeg">mpeg</option>
                  <option value="3gp">3gp</option>
                </Form.Control>
                <Form.Control.Feedback type="invalid">
                  {errors.outputFormat}
                </Form.Control.Feedback>
              </Form.Group>
            </Form.Row>
            <Form.Row>
              <Form.Group as={Col} md="12" controlId="video">
                <input
                  type="file"
                  style={{ display: "none" }}
                  ref={fileRef}
                  onChange={onChange}
                  name="video"
                />
                <ButtonToolbar>
                  <Button
                    className="button"
                    onClick={openFileDialog}
                    type="button"
                  >
                    Upload
                  </Button>
                  <span>{fileName}</span>
                </ButtonToolbar>
              </Form.Group>
            </Form.Row>
            <Button type="submit">Add Job</Button>
          </Form>
        )}
      </Formik>
      <br />
      <Table>
        <thead>
          <tr>
            <th>File Name</th>
            <th>Converted File</th>
            <th>Output Format</th>
            <th>Status</th>
            <th>Start</th>
            <th>Cancel</th>
            <th>Delete</th>
          </tr>
        </thead>
        <tbody>
          {conversionsStore.conversions.map(c => {
            return (
              <tr>
                <td>{c.filePath}</td>
                <td>{c.status}</td>
                <td>{c.outputFormat}</td>
                <td>
                  {c.convertedFilePath ? (
                    <a href={`${APIURL}/${c.convertedFilePath}`}>Open</a>
                  ) : (
                    "Not Available"
                  )}
                </td>
                <td>
                  <Button
                    className="button"
                    type="button"
                    onClick={startConversionJob.bind(this, c.id)}
                  >
                    Start
                  </Button>
                </td>
                <td>
                  <Button
                    className="button"
                    type="button"
                    onClick={cancelConversionJob.bind(this, c.id)}
                  >
                    Cancel
                  </Button>
                </td>
                <td>
                  <Button
                    className="button"
                    type="button"
                    onClick={deleteConversionJob.bind(this, c.id)}
                  >
                    Delete
                  </Button>
                </td>
              </tr>
            );
          })}
        </tbody>
      </Table>
    </div>
  );
}
export default observer(HomePage);
END


      $write->(File::Spec->catfile('src', 'request.js'), <<'END');
const axios = require("axios");
export const APIURL = "http://localhost:3000";
export const getJobs = () => axios.get(`${APIURL}/conversions`);
export const addJob = data =>
  axios({
    method: "post",
    url: `${APIURL}/conversions`,
    data,
    config: { headers: { "Content-Type": "multipart/form-data" } }
  });
export const cancel = id => axios.put(`${APIURL}/conversions/cancel/${id}`, {});
export const deleteJob = id =>
  axios.delete(`${APIURL}/conversions/${id}`);
export const startJob = id => axios.get(`${APIURL}/conversions/start/${id}`);
END

      $write->(File::Spec->catfile('src', 'store.js'), <<'END');
import { observable, action, makeObservable } from "mobx";
class ConversionsStore {
  conversions = [];
  setConversions(conversions) {
    this.conversions = conversions;
  }
}
ConversionsStore = makeObservable(ConversionsStore, {
  conversions: observable,
  setConversions: action
});
export { ConversionsStore };
END


      $write->(File::Spec->catfile('src', 'TopBar.js'), <<'END');
import React from "react";
import Navbar from "react-bootstrap/Navbar";
import Nav from "react-bootstrap/Nav";
function TopBar() {
  return (
    <Navbar bg="primary" expand="lg" variant="dark">
      <Navbar.Brand href="#home">Video Converter</Navbar.Brand>
      <Navbar.Toggle aria-controls="basic-navbar-nav" />
      <Navbar.Collapse id="basic-navbar-nav">
        <Nav className="mr-auto">
          <Nav.Link href="/">Home</Nav.Link>
        </Nav>
      </Navbar.Collapse>
    </Navbar>
  );
}
export default TopBar;
END

      $write->(File::Spec->catfile('public', 'index.html'), <<'END');
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <link rel="shortcut icon" href="%PUBLIC_URL%/favicon.ico" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta
      name="description"
      content="Web site created using create-react-app"
    />
    <link rel="apple-touch-icon" href="logo192.png" />
    <!--
      manifest.json provides metadata used when your web app is installed on a
      user's mobile device or desktop. See https://developers.google.com/web/fundamentals/web-app-manifest/
    -->
    <link rel="manifest" href="%PUBLIC_URL%/manifest.json" />
    <!--
      Notice the use of %PUBLIC_URL% in the tags above.
      It will be replaced with the URL of the `public` folder during the build.
      Only files inside the `public` folder can be referenced from the HTML.
Unlike "/favicon.ico" or "favicon.ico", "%PUBLIC_URL%/favicon.ico" will
      work correctly both with client-side routing and a non-root public URL.
      Learn how to configure a non-root public URL by running `npm run build`.
    -->
    <title>Video Converter</title>
    <link
      rel="stylesheet"
      href="https://maxcdn.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css"
      integrity="sha384-ggOyR0iXCbMQv3Xipma34MD+dH/1fQ784/j6cY/iJTQUOhcWr7x9JvoRxT2MZw1T"
      crossorigin="anonymous"
    />
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
    <!--
      This HTML file is a template.
      If you open it directly in the browser, you will see an empty page.
You can add webfonts, meta tags, or analytics to this file.
      The build step will place the bundled scripts into the <body> tag.
To begin the development, run `npm start` or `yarn start`.
      To create a production bundle, use `npm run build` or `yarn build`.
    -->
  </body>
</html>
END

      $cmd->('npm', 'i', '-g', 'nodemon');
    }
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

sub debug (@) {
    print STDERR "@_\n"
        if $verbose > 0;
}




