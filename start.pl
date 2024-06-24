use strict;
use warnings;
# /var/www/faxserver5/cgi-bin/UserAgent/
my $exec_str = 'perl main.pl  --define fax_id=FaxGateway --define start_url=https://login.easybell.de/fax --define user_login=support@abacus-service.com --define user_password=Freelancer24! --define fax_number=0049721509666000 --define upload_dir=https://login.easybell.de/fax_Senden/upload --define path_to_pdf=/var/www/faxserver5/faxein/3089612/3089612-01.pdf --define confirmation_email=support@abacus-service.com';
my $exec_res = `$exec_str`;

if ($exec_res=~/^ok/i)
{
	print "OK";
	# everything is ok
}
else
{
	# there is problem with execution, more information can be obtained from log
	# $message contains info about error
	my ($message) = $exec_res=~/NOK\:(.+)/i;

	print "ERROR:". $message;

	
}


