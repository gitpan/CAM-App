use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
              'NAME'		=> 'CAM::App',
              'VERSION_FROM'	=> 'App.pm', # finds $VERSION
              'PREREQ_PM'		=> {
                 'CGI'             => 2.00,
                 'CAM::Template'   => 0.76,

                 ## Optional
                 #'CGI::Cookie'              => 1.00,
                 #'CGI::Compress::Gzip'      => 0.11,
                 #'DBI'                      => 1.10,
                 #'CAM::Session'             => 0.01,
                 #'CAM::SQLManager'          => 0.01,
                 #'CAM::SQLObject'           => 0.01,
                 #'CAM::EmailTemplate'       => 0.15,
                 #'CAM::EmailTemplate::SMTP' => 0.20,
                 #'CAM::Template::Cache'     => 0.11,
              },
              ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
               (ABSTRACT_FROM => 'App.pm', # retrieve abstract from module
                AUTHOR     => 'Chris Dolan <chris@clotho.com>') : ()),
              );
