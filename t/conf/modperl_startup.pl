# WARNING: this file is generated, do not edit
# 01: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestConfig.pm:694
# 02: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestConfig.pm:711
# 03: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestConfigPerl.pm:130
# 04: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestConfig.pm:405
# 05: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestConfig.pm:420
# 06: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestConfig.pm:1202
# 07: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestRun.pm:398
# 08: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestRunPerl.pm:31
# 09: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestRun.pm:569
# 10: /usr/local/lib/perl5/site_perl/5.6.1/mach/Apache/TestRun.pm:569
# 11: t/TEST:10

BEGIN {
    use lib '/usr/home/jgsmith/sf.net/gestinanna/uttu/t';
    for my $file (qw(modperl_inc.pl modperl_extra.pl)) {
        eval { require "conf/$file" } or
            die if grep { -e "$_/conf/$file" } @INC;
    }
}

1;
