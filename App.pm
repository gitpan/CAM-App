package CAM::App;

=head1 NAME

CAM::App - Web database application framework

=head1 SYNOPSIS

  use CAM::App;
  require "./Config.pm";  # user-edited config hash

  my $app = CAM::App->new(Config->new(), CGI->new());
  if (!$app->authenticate()) {
    exit;
  }
  my $tmpl = $app->template("message.tmpl");
  my $ans = $app->{cgi}->param('ans');
  if (!$ans) {
     $tmpl->addParams(msg => "What is your favorite color?");
  } elsif ($ans eq "blue") {
     $tmpl->addParams(msg => "Very good.");
  } else {
     $tmpl->addParams(msg => "AIIEEEEE!");
  }
  $tmpl->print();

=head1 DESCRIPTION

CAM::App is a framework for web-based, database-driven applications.
This package abstracts away a lot of the tedious interaction with the
application configuration state.  It is quite generic, and is designed
to be subclassed with more specific functions overriding its behavior.

=cut

#--------------------------------#

require 5.005_62;
use strict;
use warnings;
use Carp;
use CGI;

## These are loaded on-demand below, if they are not already loaded.
## Please keep this list up to date!
#use DBI;
#use CAM::Template;
#use CAM::EmailTemplate;
#use CAM::EmailTemplate::SMTP;
#use CAM::Template::Cache;
#use CAM::Session;

# The following modules may loaded externally, if at all.  This module
# detects their presence by looking for their $VERSION variables.
#   CAM::Session
#   CAM::SQLManager
#   CAM::Template::Cache

use Exporter;

our @ISA = qw(Exporter);
our $VERSION = '0.03';

### Package globals
my %global_dbh_cache = ();  # used to hold DBH objects created by this package

#--------------------------------#

=head1 FUNCTIONS 

=over 4

=cut

#--------------------------------#

=item new config => CONFIGURATION, [cgi => CGI], [dbi => DBI], [session => SESSION]

Create a new application instance.  The configuration object must be a
hash reference (blessed or unblessed, it doesn't matter).  Included in
this distibution is the example/SampleConfig.pm module that shows what
sort of config data should be passed to this constructor.

Optional objects will be accepted as arguments; otherwise they will be
created as needed.

=cut

sub new
{
   my $pkg = shift;
   my %params = (@_);

   my $self = {
      session => $params{session},
      dbi => $params{dbh},
      cgi => $params{cgi},
      config => $params{config},
   };
   
   $self = bless($self, $pkg);
   $SIG{__DIE__} = sub {$self->{dying}=1;$self->error(@_)};

   if (!$self->{cgi})
   {
      $self->{cgi} = CGI->new();
   }
   if ($self->{dbh})
   {
      # Note that unlike getDBH(), the DBH is NOT cached in this case.
      # This is the correct behavior.  Since the calling script handed
      # us the DBH, it's assumed that the caller will handle any
      # caching

      $self->_applyDBH();
   }
   if ($CAM::SQLManager::VERSION && $self->{config}->{sqldir})
   {
      CAM::SQLManager->setDirectory($self->{config}->{sqldir});
   }

   return $self;
}

#--------------------------------#

=item authenticate

Test the login information, if any.  Currently no tests are performed
-- this is a no-op.  Subclasses may override this method to test login
credentials.  Even though it's currently trivial, subclass methods
should alway include the line:

    return undef if (!$self->SUPER::Authenticate());

In case the parent authenticate() method adds a test in the future.

=cut

sub authenticate {
   my $self = shift;

   # No checks

   return $self;
}

#--------------------------------#

=item header

Compose and return a CGI header.  Returns the empty string if the
header has already been printed.

=cut

sub header {
   my $self = shift;

   if (!$self->{cgi}->{'.header_printed'}) {
      return $self->{cgi}->header(
                                  ($self->{cookie} ? 
                                   (-cookie => $self->{cookie}) : ()),
                                  @_,
                                  );
   } else {
      return "";
   }
}
#--------------------------------#

=item isAllowedHost

This function is called from authenticate().  Checks the incoming host
and returns false if it should be blocked.  Currently no tests are
performed -- this is a no-op.  Subclasses may override this behavior.

=cut

sub isAllowedHost {
   my $self = shift;

   # For now, let any host view the site
   # Return undef to block access to a host
   return $self;
}
#--------------------------------#

=item getConfig

Returns the configuration hash.

=cut

sub getConfig
{
   my $self = shift;
   return $self->{config};
}
#--------------------------------#

=item getCGI

Returns the CGI object.

=cut

sub getCGI
{
   my $self = shift;
   return $self->{cgi};
}
#--------------------------------#

=item getDBH

Return a DBI handle.  This object is created, if one does not already
exist, using the parameters from the configuration hash to initialize
a DBI object.  The config variables 'dbusername' and 'dbpassword' are
used, along with either 'dbistr' (if present) or 'dbname' and
'dbhost'.

If no 'dbistr' is specified via config, MySQL is assumed.  The DBI
handle is cached in the package for future use.  This means that under
mod_perl, the database connection only needs to be opened once.

=cut

sub getDBH
{
   my $self = shift;

   my $cfg = $self->{config};
   if ((!$self->{dbh}) && ($cfg->{dbistr} || $cfg->{dbname}) &&
       $cfg->{dbusername})
   {
      if (!$self->loadModule("DBI"))
      {
         $self->error("Internal error: Failed to load the DBI library");
      }

      my $dbistr = $cfg->{dbistr};
      if (!$dbistr)
      {
         $dbistr = "DBI:mysql:database=".$cfg->{dbname};
         $dbistr .= ";host=".$cfg->{dbhost} if ($cfg->{dbhost});
      }

      # First try to retrieve a global dbh object, shared between
      # CAM::App objects, or left over from a previous mod_perl run.
      # Construct a unique key from the connection parameters

      my $cache_key = $dbistr . ";username=".$cfg->{dbusername};

      if ($global_dbh_cache{$cache_key})
      {
         $self->{dbh} = $global_dbh_cache{$cache_key};
      }
      else
      {
         my $passwd = $cfg->{dbpassword};
         $passwd = "" if (!defined $passwd);  # fix possible undef
         $self->{dbh} = DBI->connect($dbistr,
                                     $cfg->{dbusername}, $passwd,
                                     {autocommit => 0, RaiseError => 1});
         if (!$self->{dbh})
         {
            $self->error("Failed to connect to the database: " . 
                         ($DBI::errstr || $! || "(unknown error)"));
         }
         $self->_applyDBH();
         $global_dbh_cache{$cache_key} = $self->{dbh};
      }
   }
   return $self->{dbh};
}

#--------------------------------#
# Internal function:
# Tell other packages to use this new DBH object.

sub _applyDBH
{
   my $self = shift;

   my $dbh = $self->{dbh};
   if ($dbh)
   {
      CAM::Session->setDBH($dbh)         if ($CAM::Session::VERSION);
      CAM::SQLManager->setDBH($dbh)      if ($CAM::SQLManager::VERSION);
      CAM::Template::Cache->setDBH($dbh) if ($CAM::Template::Cache::VERSION);
   }
}
#--------------------------------#

=item getSession

Return a CAM::Session object for this application.  If one has not yet
been created, make one now.  Note!  This must be called before the CGI
header is printed, if at all.

=cut

sub getSession
{
   my $self = shift;

   if (!$self->{session})
   {
      if (!$self->loadModule("CAM::Session"))
      {
         $self->error("Internal error: Failed to load the CAM::Session library");
      }

      if ($self->{config}->{cookiename})
      {
         CAM::Session->setCookieName($self->{config}->{cookiename});
      }
      if ($self->{config}->{sessiontable})
      {
         CAM::Session->setTableName($self->{config}->{sessiontable});
      }
      if ($self->{config}->{sessiontime})
      {
         CAM::Session->setExpiration($self->{config}->{sessiontime});
      }
      CAM::Session->setDBH($self->getDBH());
      $self->{session} = CAM::Session->new();
   }
   return $self->{session};
}
#--------------------------------#

=item getTemplate FILE, [KEY => VALUE, KEY => VALUE, ...]

Creates, prefills and returns a CAM::Template object.  The FILE should
be the template filename relative to the template directory specified
in the Config file.

See the prefillTemplate() method to see which key-value pairs are
preset.

=cut

sub getTemplate {
   my $self = shift;
   my $file = shift;

   return $self->_template("CAM::Template", $file, undef, @_);
}
#--------------------------------#

=item getTemplateCache CACHEKEY, FILE, [KEY => VALUE, KEY => VALUE, ...]

Creates, prefills and returns a CAM::Template::Cache object.  The
CACHEKEY should be the unique string that identifies the filled
template in the database cache.

=cut

sub getTemplateCache {
   my $self = shift;
   my $key = shift;
   my $file = shift;

   return $self->_template("CAM::Template::Cache", $file, $key, @_);
}
#--------------------------------#

=item getEmailTemplate FILE, [KEY => VALUE, KEY => VALUE, ...]

Creates, prefills and returns a CAM::EmailTemplate object.  This is
very similar to the template() method.

If the 'mailhost' config variable is set, this instead uses
CAM::EmailTemplate::SMTP.

=cut

sub getEmailTemplate {
   my $self = shift;
   my $file = shift;

   my $module = "CAM::EmailTemplate";
   if ($self->{config}->{mailhost})
   {
      $module = "CAM::EmailTemplate::SMTP";
      if (!$self->loadModule($module))
      {
         $self->error("Internal error: Failed to load the $module library" .
                      ( $self->{load_error} ? "($$self{load_error})" : "" ));
      }
      CAM::EmailTemplate::SMTP->setHost($self->{config}->{mailhost});
   }
   return $self->_template($module, $file, undef, @_);
}

#--------------------------------#
# Internal function:
# builds, fills and returns a template object

sub _template {
   my $self = shift;
   my $module = shift || "CAM::Template";
   my $file = shift;
   my $key = shift;

   if (!$self->loadModule($module))
   {
      $self->error("Internal error: Failed to load the $module library")
          unless ($self->{in_error});
   }

   my $template;
   if ($key)
   {
      # This is a ::Cache template
      $template = $module->new($key, $self->getDBH());
   }
   else
   {
      # This is a normal template
      $template = $module->new();
   }

   my $path = $self->{config}->{templatepath};
   $path .= "/" if ($path && $path !~ /\/$/);
   if (!$template->setFilename($path . $file))
   {
      $self->error("Internal error: problem locating the web page template")
          unless ($self->{in_error});
   }
   $self->prefillTemplate($template, @_);

   return $template;
}
#--------------------------------#

=item prefillTemplate TEMPLATE, [KEY => VALUE, KEY => VALUE, ...]

This fills the search-and-replace list of a template with typical
values (like the base URL, the URL of the script, etc.  Usually, it is
just called from withing getTemplate() and related methods, but if you
build your own templates you may want to use this explicitly.

The following value are set (and the order is significant, since later
keys can override earlier ones):

   - the configuration variables
   - mod_perl => boolean indicating whether the script is in mod_perl mode
   - myURL => URL of the current script
   - anything passed as arguments to this method

Subclasses may override this to add more fields to the template.  We
recommend implementing override methods like this:

    sub prefillTemplate {
      my $self = shift;
      my $template = shift;
      
      $self->SUPER::prefillTemplate($template);
      $template->addParams(
                           myparam => myvalue,
                           # any other key-value pairs or hashes ...

                           @_,  # add this LAST to override any earlier params
                           );
      return $self;
    }

=cut

sub prefillTemplate
{
   my $self = shift;
   my $template = shift;

   if (!$template->setParams(

                             # you MUST update the documentation above
                             # if you change anything in this list!!!

                             %{$self->{config}},
                             mod_perl => (exists $ENV{MOD_PERL}),
                             myURL => $self->{cgi}->url(),
                             @_,
                             ))
   {
      $self->error("Internal error: problem setting template parameters")
          unless ($self->{in_error});
   }
   return $self;
}
#--------------------------------#

=item error MSG

Prints an error message to the browser and exits.

If the 'error_template' configuration parameter is set, then that
template is used to display the error.  In that case, the error
message will me substituted into the ::error:: template variable.

For the sake of your error template HTML layout, use these guidelines:

   1) error messages do not end with puncuation
   2) error messages might be multiline (with <br> tags, for example)
   3) this function prepares the message for HTML display 
      (like escaping "<" and ">" for example).

=cut

sub error {
   my $self = shift;
   my $msg = shift;

   $msg = $self->{cgi}->escapeHTML($msg);
   $msg =~ s/\n/<br>\n/gs;

   if ($self->{in_error})
   {
      die "Error function called too many times";
   }
   $self->{in_error} = 1;  # Flag so we don't call error() recursively

   print $self->header();
   my $tmplFilename = $self->{config}->{error_template};
   my $errTmpl;

   if ($tmplFilename)
   {
      $errTmpl = $self->getTemplate($tmplFilename, error => $msg);
   }

   if (!$errTmpl)
   {
      print "Internal error: $msg<br>\n ";
   }
   else
   {
      $errTmpl->print();
   }

   confess if ($self->{dying});
   delete $self->{in_error};
   exit;
}
#--------------------------------#

=item loadModule MODULE

Load a perl module, returning a boolean indicating success or failure.
Shortcuts are taken if the module is already loaded, or loading has
previously failed.

=cut

sub loadModule {
   my $self = shift;
   my $module = shift;

   # Get a reference to the module VERSION variable
   my $ver_ref = eval "\\\$${module}::VERSION";
   delete $self->{load_error};  # clear if it was previously set
   if (!defined $$ver_ref) {
      local $SIG{__WARN__} = 'DEFAULT';
      local $SIG{__DIE__} = 'DEFAULT';
      eval "use $module;";
      if ($@ || (!defined $$ver_ref)) {
         $self->{load_error} = "$@" if ($@);
         $$ver_ref = 0;
      }
   }
   return $$ver_ref;
}
#--------------------------------#

1;
__END__

=back

=head1 AUTHOR

Chris Dolan, Clotho Advanced Media, I<chris@clotho.com>

=cut
