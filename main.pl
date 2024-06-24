use strict;
use warnings;
use WWW::Mechanize::Chrome;
use Log::Log4perl;
use FindBin;
use lib $FindBin::Bin;
use JSON;
use File::Basename;
use Getopt::Long;

my $CURRENT_DIR = $FindBin::Bin;
my $APP_VERSION = "1.8";

Log::Log4perl->init("$CURRENT_DIR/log.conf");
my $logger = Log::Log4perl->get_logger();

$logger->info("Start execution. App version=$APP_VERSION");

my $APP_CONFIG = {};
GetOptions ("define=s" => $APP_CONFIG);

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

# Create a new WWW::Mechanize::Chrome object
my $mech = WWW::Mechanize::Chrome->new(
    headless => 1,  # Run in headless mode
);

$logger->debug("Navigating to " . $APP_CONFIG->{"start_url"});
$mech->get($APP_CONFIG->{"start_url"});

# Wait for the form to load
$mech->wait_until_visible('input[placeholder="Kundennummer oder andere Option"]');

# Fill in the form fields
$mech->field("Kundennummer oder andere Option", $APP_CONFIG->{"user_login"});
$mech->field("Passwort", $APP_CONFIG->{"user_password"});

# Submit the form
$mech->click('button[data-test="submit"]');

# Check if login was successful
if ($mech->content !~ /logout/) {
    print "NOK: Login failed\n";
    exit(1);
}

# Navigate to the fax sending page
$mech->get("https://login.easybell.de/fax_Senden");

# Wait for the form to load
$mech->wait_until_visible('form');

# Upload the PDF file
my($file_name, $dirs, $suffix) = fileparse($APP_CONFIG->{path_to_pdf});
$mech->form_number(1);  # Select the form (assuming the first form is the correct one)
$mech->field("file", [$APP_CONFIG->{path_to_pdf}, $file_name]);

# Submit the form to upload the file
$mech->click('button[type="submit"]');

# Wait for the upload to complete and get the response
my $upload_response = $mech->content;
$logger->debug("Upload response: $upload_response");

if ($upload_response !~ /success/) {
    print "NOK: File upload failed\n";
    exit(1);
}

# Extract the uploaded file path from the response
my $uploaded_path = decode_json($upload_response)->{path};

# Prepare the fax sending request
my $number = get_number_of_fax($APP_CONFIG->{fax_number});
my $token = extract_token($mech->content);  # Assuming the token can be extracted from the page content

# Send the fax
$mech->submit_form(
    form_number => 1,
    fields      => {
        "_token"                  => $token,
        "sender"                  => $APP_CONFIG->{"user_login"},
        "identifier"              => $APP_CONFIG->{fax_id},
        "ConfirmationEmail"       => $APP_CONFIG->{confirmation_email},
        "pdfcreate"               => $uploaded_path,
        "text"                    => "%0D%0A++++++++++++++++++++++++",
        "deactivateCalllogCallback" => "none",
        "to_" . $number           => $number,
        "tmpto"                   => "",
    }
);

# Check the response
my $response = $mech->content;
$logger->debug("Fax send response: $response");

my $res = decode_json($response);

if ($res->{'success'} =~ /true/i) {
    print "OK\n";
    exit(0);
} else {
    print "NOK: " . $res->{'data'}->{$number}->{'Message'} . "\n";
    exit(1);
}

$logger->info("End execution");

sub get_number_of_fax {
    my $number = shift;
    $number =~ s/ //g;
    $number =~ s/\\//g;
    $number =~ s/\-//g;
    $number =~ s/\|//g;
    if ($number =~ /^\\+.*$/) {
        $number = "00" . substr($number, 1);
    }
    if ($number =~ /^0049[0-9].*$/) {
        $number = "0" . substr($number, 4);
    }
    return $number;
}

sub extract_token {
    my $content = shift;
    if ($content =~ /<input type="hidden" name="_token" value="([^"]+)"/) {
        return $1;
    }
    die "Token not found in the page content";
}
