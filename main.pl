use strict;
use warnings;
use LWP::UserAgent;
use Log::Log4perl;
use FindBin;
use lib $FindBin::Bin;
use HTML::Form;
use Data::Dumper;
#use YAML::XS 'LoadFile';
use Getopt::Long;
use HTTP::Request::Common;
use JSON;
use File::Basename;


my $CURRENT_DIR = $FindBin::Bin;
my $APP_VERSION = "1.8";

Log::Log4perl->init("$CURRENT_DIR/log.conf");
my $logger = Log::Log4perl->get_logger();

$logger->info("Start execution. App version=$APP_VERSION");


#my $APP_CONFIG = LoadFile($CURRENT_DIR .'/config.yaml');

my $APP_CONFIG = {};
GetOptions ("define=s" => $APP_CONFIG);

#print Dumper ($APP_CONFIG);
#exit(0);

# to prevent possible problems with HTTPS
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
#$ENV{HTTPS_PROXY} = "http://localhost:8888";


# fake user agent to hide our script
my $ua = LWP::UserAgent->new (agent=>"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36");
my $can_accept = HTTP::Message::decodable;
$ua->cookie_jar( {} );

# make POST HTTP request redirectable for UserAgent
push @{ $ua->requests_redirectable }, 'POST';

# get page to set cookies
$logger->debug("send HTTP GET " . $APP_CONFIG->{"start_url"});


my $response = $ua->get($APP_CONFIG->{start_url});

$logger->debug("response is:");
$logger->debug(Dumper($response));

if (!$response->is_success)
{
	print "NOK";
	exit(1);
}

my @forms = HTML::Form->parse(
	$response->decoded_content,
	base => $response->base,
	charset => $response->content_charset
);

# set creadentials
$forms[0]->param("id",$APP_CONFIG->{"user_login"});
$forms[0]->param("password",$APP_CONFIG->{"user_password"});

#print Dumper ($forms[0]);

# log in
my $request = $forms[0]->click();

# send request to log in
$logger->debug("try to log in");


$response = $ua->request($request);
$logger->debug("response is:");
$logger->debug(Dumper($response));


if (!$response->is_success)
{
	print "NOK";
	exit(1);

}


my $fax_url = "https://login.easybell.de/fax_Senden";

$response = $ua->get($fax_url);

if (!$response->is_success)
{
	print "NOK";
	exit(1);
}


# forms[0] is form that send fax
@forms = HTML::Form->parse(
	$response->decoded_content,
	base => $response->base,
	charset => $response->content_charset
);


#print Dumper($forms[0]);

#print ($response->decoded_content);
#exit(0);

#print  ($response->decoded_content);


# it uploads file to the server using AJAX POST request and get back BASE 64 decoded string with the path to uploaded file


my $fields = {};


# these fields related only to the file
#$fields->{_token} = $forms[0]->param("_token");


#my $other_fields = {};
#$other_fields->{_token} = $forms[0]->param("_token");

#$fields = [$APP_CONFIG->{path_to_pdf}, "test.pdf",

my($file_name, $dirs, $suffix) = fileparse($APP_CONFIG->{path_to_pdf});


#print $forms[0];

$fields = {
	"file"=> [$APP_CONFIG->{path_to_pdf}, $file_name],
	"_token" => $forms[0]->param("_token")

};
#$fields->{name} = "file";
#$fields->{filename} = $APP_CONFIG->{path_to_pdf};


#	$fields = $config;
#	$fields->{currrentUploadDirectory} =  $config->{currrentUploadDirectory};
#	$fields->{realCurrrentUploadDirectory} = $config->{realCurrrentUploadDirectory};
#	$fields->{'uploadedfiles[]'} = $config->{'uploadedfiles[]'};


# X-Requested-With:XMLHttpRequest
$ua->default_headers->push_header('X-Requested-With','XMLHttpRequest');

my $req;

eval
{
	$req = POST($APP_CONFIG->{upload_dir},
			Content_Type=>'form-data', # trigge Form-based File Upload as specified in RFC 1867
				Content=>$fields
				);
};
if ($@)
{
	print "NOK:".$@;
	exit(1);
}


$logger->debug("req upload:");
$logger->debug(Dumper($req));

$response = $ua->request($req
#'Accept-Encoding' => $can_accept
);

$logger->debug("response:");
$logger->debug(Dumper($response));


if (!$response->is_success)
{
	print "NOK";
	exit(1);
}



my $uploaded_path = $response->decoded_content;




# now try to send fax


#_token:S89cgqwikwT5cypNVlU1E4gW8dBvFzVtDBpCBnjQ
#tmpto:
#sender:010001438457_11#004972126675900#FaxGateway
#identifier:FaxGateway
#ConfirmationEmail:sales@abacusoffice.de
#pdfcreate:fileupload
#text:

#_token:S89cgqwikwT5cypNVlU1E4gW8dBvFzVtDBpCBnjQ
#deactivateCalllogCallback:none
#to_0721509666000:0721509666000



my $number = get_number_of_fax($APP_CONFIG->{fax_number});

# to avoid replacing _ wit - in headers
local $HTTP::Headers::TRANSLATE_UNDERSCORE = 0;

#print Dumper($forms[0]);
#exit(0);


# create HTTP POST manualy because HTTP::Form doesn't support adding new field
if ($APP_CONFIG->{optimize} ==1)
{
	$req=HTTP::Request::Common::POST(
	"https://login.easybell.de/fax_Senden",
	       Content_Type => 'form-data',
		Content      => [ 	"_token" => $forms[0]->param("_token"),
		"sender" => $forms[0]->param("sender"),
#		"identifier" =>$forms[0]->param("identifier"),
		"identifier" => $APP_CONFIG->{fax_id},
		"ConfirmationEmail" => $APP_CONFIG->{confirmation_email},
		"pdfcreate" => $forms[0]->param("pdfcreate"),
		"text" => "%0D%0A++++++++++++++++++++++++",
		"deactivateCalllogCallback" => "none",
		"to_" . $number => $number,
		"tmpto" => "",
		"optimize" => 1,
		"Origin" => "https://login.easybell.de",
		"Referer" => "https://login.easybell.de/fax_Senden"
	]
	);
}
else
{
	$req=HTTP::Request::Common::POST(
	"https://login.easybell.de/fax_Senden",
	       Content_Type => 'form-data',
		Content      => [ 	"_token" => $forms[0]->param("_token"),
		"sender" => $forms[0]->param("sender"),
#		"identifier" =>$forms[0]->param("identifier"),
		"identifier" => $APP_CONFIG->{fax_id},
		"ConfirmationEmail" => $APP_CONFIG->{confirmation_email},
		"pdfcreate" => $forms[0]->param("pdfcreate"),
		"text" => "%0D%0A++++++++++++++++++++++++",
		"deactivateCalllogCallback" => "none",
		"to_" . $number => $number,
		"tmpto" => "",
		"Origin" => "https://login.easybell.de",
		"Referer" => "https://login.easybell.de/fax_Senden"
	]
	);

}





# send fax
$logger->debug("try to send fax");
$logger->debug("request:");
$logger->debug(Dumper($req));

$response = $ua->request($req);

$logger->debug("response:");
$logger->debug(Dumper($response));

if (!$response->is_success)
{
	print "NOK";
	exit(1);
}

# get JSON reponse that contain info about result of operation
my $res = decode_json ($response->decoded_content);

$logger->debug("Result is:" . Dumper($res));

#$VAR1 = {
#          'data' => {
#                      '0721509666000' => {
#                                           'Code' => '100',
#                                           'Message' => "Fax erfolgreich zum Versand \x{fc}bergeben."
#                                         }
#                    },
#          'success' => 'true'
#        };

if ($res->{'success'}=~/true/i)
{
	print "OK";
	exit(0);
}
else
{
	print "NOK:" . $res->{'data'}->{$number}->{'Message'};
	exit(1);
}


$logger->info("End execution");


# this code was translated from original JS code
# it gets number of fax
sub get_number_of_fax
{
	my $number = shift;

	$number=~s/ //g;
	$number=~s/\\//g;
	$number=~s/\-//g;
	$number=~s/\|//g;

	if ($number=~/^\\+.*$/)
	{
		$number = "00" . substr ($number,1);
	}

	if ($number=~/^0049[0-9].*$/)
	{
		$number = "0" . substr($number,4);
	}

	return $number;
}
