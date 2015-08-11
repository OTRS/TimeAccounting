# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get selenium object
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        # get helper object
        $Kernel::OM->ObjectParamAdd(
            'Kernel::System::UnitTest::Helper' => {
                RestoreSystemConfiguration => 1,
                }
        );
        my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

        # get config object
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

        # use a calendar with the same business hours for every day so that the UT runs correctly
        # on every day of the week and outside usual business hours.
        my %Week;
        my @Days = qw(Sun Mon Tue Wed Thu Fri Sat);
        for my $Day (@Days) {
            $Week{$Day} = [ 0 .. 23 ];
        }
        $ConfigObject->Set(
            Key   => 'TimeWorkingHours',
            Value => \%Week,
        );
        $Kernel::OM->Get('Kernel::System::SysConfig')->ConfigItemUpdate(
            Valid => 1,
            Key   => 'TimeWorkingHours',
            Value => \%Week,
        );

        # create test user and login
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users', 'time_accounting' ],
        ) || die "Did not get test user";

        # get test user ID
        my $TestUserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
            UserLogin => $TestUserLogin,
        );

        # get time accounting object
        my $TimeAccountingObject = $Kernel::OM->Get('Kernel::System::TimeAccounting');

        # insert test user into account setting
        $TimeAccountingObject->UserSettingsInsert(
            UserID => $TestUserID,
            Period => '1',
        );

        # get time object
        my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

        # get current system test time
        my ( $SecCurrent, $MinCurrent, $HourCurrent, $DayCurrent, $MonthCurrent, $YearCurrent )
            = $TimeObject->SystemTime2Date(
            SystemTime => $TimeObject->SystemTime(),
            );

        # update user time account setting
        $TimeAccountingObject->UserSettingsUpdate(
            UserID        => $TestUserID,
            Description   => 'Selenium test accounting user',
            CreateProject => 1,
            ShowOvertime  => 1,
            Period        => {
                1 => {
                    DateStart   => "$YearCurrent-$MonthCurrent-$DayCurrent",
                    DateEnd     => "$YearCurrent-$MonthCurrent-$DayCurrent",
                    WeeklyHours => '38',
                    LeaveDays   => '25',
                    Overtime    => '38',
                    UserStatus  => 1,
                },
                }
        );

        # create test project
        my $ProjectTitle = 'Project ' . $Helper->GetRandomID();
        my $ProjectID    = $TimeAccountingObject->ProjectSettingsInsert(
            Project            => $ProjectTitle,
            ProjectDescription => 'Selenium test project',
            ProjectStatus      => 1,
        );

        # create test action
        my $ActionTitle = 'Action ' . $Helper->GetRandomID();
        $TimeAccountingObject->ActionSettingsInsert(
            Action       => $ActionTitle,
            ActionStatus => 1,
        );
        my %ActionData = $TimeAccountingObject->ActionGet(
            Action => $ActionTitle,
        );
        my $ActionID = $ActionData{ID};

        # log in test user
        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get script alias
        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        # navigate to AgentTimeAccountingEdit
        $Selenium->get("${ScriptAlias}index.pl?Action=AgentTimeAccountingEdit");

        # add addional row
        $Selenium->find_element("//button[\@id='MoreInputFields'][\@type='button']")->click();

        # check time accounting edit field IDs, first and added row
        for my $Row ( 1, 9 ) {
            for my $EditFieldID (
                qw(ProjectID ActionID Remark StartTime EndTime Period)
                )
            {
                my $Element = $Selenium->find_element( "#$EditFieldID$Row", 'css' );
                $Element->is_enabled();
                $Element->is_displayed();
            }
        }
        for my $EditRestID (
            qw(Month Day Year DayDatepickerIcon NavigationSelect LeaveDay Sick Overtime)
            )
        {
            my $Element = $Selenium->find_element( "#$EditRestID", 'css' );
            $Element->is_enabled();
            $Element->is_displayed();
        }

        # edit time accounting for test created user
        $Selenium->find_element( "#ProjectID1_Search", 'css' )->click();
        sleep 1;
        $Selenium->find_element("//*[text()='$ProjectTitle']")->click();
        $Selenium->find_element( "#ActionID1_Search", 'css' )->click();
        sleep 1;
        $Selenium->find_element("//*[text()='$ActionTitle']")->click();
        $Selenium->find_element( "#StartTime1", 'css' )->send_keys('10:00');
        $Selenium->find_element( "#EndTime1",   'css' )->send_keys('16:00');
        $Selenium->find_element( "#Remark1",    'css' )->send_keys('Selenium test remark');

        # verify that period calculate correct time
        $Self->Is(
            $Selenium->find_element( "#Period1", 'css' )->get_value(),
            '6.00',
            "Period time correctly calculated",
        );

        # submit work accounting edit time record
        $Selenium->find_element("//button[\@value='Submit'][\@type='submit']")->click();

        # verify submit message
        my $SubmitMessage = 'Successful insert!';
        $Self->True(
            index( $Selenium->get_page_source(), $SubmitMessage ) > -1,
            "$SubmitMessage - found",
        );

        # get DB object
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

        # get DB clean-up data
        my @DBCleanData = (
            {
                Quoted  => $ProjectTitle,
                Table   => 'time_accounting_project',
                Where   => 'project',
                Bind    => '',
                Message => "$ProjectTitle - deleted",
            },
            {
                Quoted  => $ActionTitle,
                Table   => 'time_accounting_action',
                Where   => 'action',
                Bind    => '',
                Message => "$ActionTitle - deleted",
            },
            {
                Table   => 'time_accounting_table',
                Where   => 'user_id',
                Bind    => $TestUserID,
                Message => "Test user $TestUserID - removed from accounting table",
            },
            {
                Table   => 'time_accounting_user',
                Where   => 'user_id',
                Bind    => $TestUserID,
                Message => "Test user $TestUserID - removed from accounting setting",
            },
            {
                Table   => 'time_accounting_user_period',
                Where   => 'user_id',
                Bind    => $TestUserID,
                Message => "Test user $TestUserID - removed from accounting period",
            },
        );

        # clean system from test created data
        for my $Delete (@DBCleanData) {
            if ( $Delete->{Quoted} ) {
                $Delete->{Bind} = $DBObject->Quote( $Delete->{Quoted} );
            }
            my $Success = $DBObject->Do(
                SQL  => "DELETE FROM $Delete->{Table} WHERE $Delete->{Where} = ?",
                Bind => [ \$Delete->{Bind} ],
            );
            $Self->True(
                $Success,
                $Delete->{Message},
            );
        }
    }
);

1;
