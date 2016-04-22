# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentTimeAccountingView;

use strict;
use warnings;

use Date::Pcalc qw(Today Days_in_Month Day_of_Week Add_Delta_YMD check_date);
use Time::Local;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my @MonthArray = (
        '',     'January', 'February', 'March',     'April',   'May',
        'June', 'July',    'August',   'September', 'October', 'November',
        'December',
    );
    my @WeekdayArray = ( 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', );

    # ---------------------------------------------------------- #
    # view older day inserts
    # ---------------------------------------------------------- #

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # permission check
    if ( !$Self->{AccessRo} ) {
        return $LayoutObject->NoPermission(
            WithHeader => 'yes',
        );
    }

    # get params
    for my $Parameter (qw(Day Month Year UserID)) {
        $Param{$Parameter} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => $Parameter );
    }

    # check needed params
    for my $Needed (qw(Day Month Year)) {
        if ( !$Param{$Needed} ) {

            return $LayoutObject->ErrorScreen(
                Message => $LayoutObject->{LanguageObject}->Translate('View: Need %s!', $Needed),
            );
        }
    }

    # format the date parts
    $Param{Year}  = sprintf( "%02d", $Param{Year} );
    $Param{Month} = sprintf( "%02d", $Param{Month} );
    $Param{Day}   = sprintf( "%02d", $Param{Day} );

    # if no UserID posted use the current user
    $Param{UserID} ||= $Self->{UserID};

    # get time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # get current date and time
    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );

    my $MaxAllowedInsertDays = $Kernel::OM->Get('Kernel::Config')->Get('TimeAccounting::MaxAllowedInsertDays') || '10';
    ( $Param{YearAllowed}, $Param{MonthAllowed}, $Param{DayAllowed} )
        = Add_Delta_YMD( $Year, $Month, $Day, 0, 0, -$MaxAllowedInsertDays );

    # redirect to the edit screen, if necessary
    if (
        timelocal( 1, 0, 0, $Param{Day}, $Param{Month} - 1, $Param{Year} - 1900 ) > timelocal(
            1, 0, 0, $Param{DayAllowed},
            $Param{MonthAllowed} - 1,
            $Param{YearAllowed} - 1900
        ) && $Param{UserID} == $Self->{UserID}
        )
    {

        return $LayoutObject->Redirect(
            OP =>
                "Action=AgentTimeAccountingEdit;Year=$Param{Year};Month=$Param{Month};Day=$Param{Day}",
        );
    }

    # show the naming of the agent which time accounting is visited
    if ( $Param{UserID} != $Self->{UserID} ) {
        my %ShownUsers = $Kernel::OM->Get('Kernel::System::User')->UserList(
            Type  => 'Long',
            Valid => 1
        );
        $Param{User} = $ShownUsers{ $Param{UserID} };
        $LayoutObject->Block(
            Name => 'User',
            Data => {%Param},
        );
    }

    $Param{Weekday}         = Day_of_Week( $Param{Year}, $Param{Month}, $Param{Day} );
    $Param{Weekday_to_Text} = $WeekdayArray[ $Param{Weekday} - 1 ];
    $Param{Month_to_Text}   = $MonthArray[ $Param{Month} ];

    # Values for the link icons <>
    ( $Param{YearBack}, $Param{MonthBack}, $Param{DayBack} )
        = Add_Delta_YMD( $Param{Year}, $Param{Month}, $Param{Day}, 0, 0, -1 );
    ( $Param{YearNext}, $Param{MonthNext}, $Param{DayNext} )
        = Add_Delta_YMD( $Param{Year}, $Param{Month}, $Param{Day}, 0, 0, 1 );

    $Param{DateSelection} = $LayoutObject->BuildDateSelection(
        %Param,
        Prefix   => '',
        Format   => 'DateInputFormat',
        Validate => 1,
        Class    => $Param{Errors}->{DateInvalid},
    );

    # get time accounting object
    my $TimeAccountingObject = $Kernel::OM->Get('Kernel::System::TimeAccounting');

    # Show Working Units
    # get existing working units
    my %Data = $TimeAccountingObject->WorkingUnitsGet(
        Year   => $Param{Year},
        Month  => $Param{Month},
        Day    => $Param{Day},
        UserID => $Param{UserID},
    );

    $Param{Date} = $Data{Date};

    # get project and action settings
    my %Project = $TimeAccountingObject->ProjectSettingsGet();
    my %Action  = $TimeAccountingObject->ActionSettingsGet();

    # get sick, leave day and overtime
    $Param{Sick}     = $Data{Sick}     ? 'checked' : '';
    $Param{LeaveDay} = $Data{LeaveDay} ? 'checked' : '';
    $Param{Overtime} = $Data{Overtime} ? 'checked' : '';

    # only show the unit block if there is some data
    my $UnitsRef = $Data{WorkingUnits};
    if ( $UnitsRef->[0] ) {

        for my $UnitRef ( @{$UnitsRef} ) {

            $LayoutObject->Block(
                Name => 'Unit',
                Data => {
                    Project   => $Project{Project}{ $UnitRef->{ProjectID} },
                    Action    => $Action{ $UnitRef->{ActionID} }{Action},
                    Remark    => $UnitRef->{Remark},
                    StartTime => $UnitRef->{StartTime},
                    EndTime   => $UnitRef->{EndTime},
                    Period    => $UnitRef->{Period},
                },
            );
        }

        $LayoutObject->Block(
            Name => 'Total',
            Data => {
                Total => sprintf( "%.2f", $Data{Total} ),
            },
        );
    }
    else {
        $LayoutObject->Block(
            Name => 'NoDataFound',
            Data => {},
        );
    }

    if ( $Param{Sick} || $Param{LeaveDay} || $Param{Overtime} ) {
        $LayoutObject->Block(
            Name => 'OtherTimes',
            Data => {
                Sick     => $Param{Sick},
                LeaveDay => $Param{LeaveDay},
                Overtime => $Param{Overtime},
            },
        );
    }

    my %UserData = $TimeAccountingObject->UserGet(
        UserID => $Param{UserID},
    );

    my $Vacation = $TimeObject->VacationCheck(
        Year     => $Param{Year},
        Month    => $Param{Month},
        Day      => $Param{Day},
        Calendar => $UserData{Calendar},
    );

    if ($Vacation) {
        $LayoutObject->Block(
            Name => 'Vacation',
            Data => {
                Vacation => $Vacation,
            },
        );
    }

    # presentation
    my $Output = $LayoutObject->Header(
        Title => 'View',
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        Data         => \%Param,
        TemplateFile => 'AgentTimeAccountingView'
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

1;
