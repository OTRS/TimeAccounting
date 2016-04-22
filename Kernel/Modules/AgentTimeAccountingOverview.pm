# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentTimeAccountingOverview;

use strict;
use warnings;

use Date::Pcalc qw(Today Days_in_Month Day_of_Week Add_Delta_YMD check_date);
use Kernel::Language qw(Translatable);
use Time::Local;

use Kernel::System::VariableCheck qw(:all);

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

    # get time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # ---------------------------------------------------------- #
    # overview about the users time accounting
    # ---------------------------------------------------------- #
    my ( $Sec, $Min, $Hour, $CurrentDay, $Month, $Year ) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # permission check
    if ( !$Self->{AccessRo} ) {
        return $LayoutObject->NoPermission(
            WithHeader => 'yes',
        );
    }

    for my $Parameter (qw(Status Day Month Year UserID ProjectStatusShow)) {
        $Param{$Parameter} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => $Parameter );
    }
    $Param{Action} = 'AgentTimeAccountingEdit';

    if ( !$Param{UserID} ) {
        $Param{UserID} = $Self->{UserID};
    }
    else {
        if ( $Param{UserID} != $Self->{UserID} && !$Self->{AccessRw} ) {

            return $LayoutObject->NoPermission(
                WithHeader => 'yes',
            );
        }
        $Param{Action} = 'AgentTimeAccountingView';
    }
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

    # Check Date
    if ( !$Param{Year} || !$Param{Month} ) {
        $Param{Year}  = $Year;
        $Param{Month} = $Month;
    }
    else {
        $Param{Month} = sprintf( "%02d", $Param{Month} );
    }

    # store last screen
    $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreen',
        Value =>
            "Action=$Self->{Action};Year=$Param{Year};Month=$Param{Month}",
    );

    $Param{Month_to_Text} = $MonthArray[ $Param{Month} ];

    ( $Param{YearBack}, $Param{MonthBack}, $Param{DayBack} )
        = Add_Delta_YMD( $Param{Year}, $Param{Month}, 1, 0, -1, 0 );
    ( $Param{YearNext}, $Param{MonthNext}, $Param{DayNext} ) = Add_Delta_YMD( $Param{Year}, $Param{Month}, 1, 0, 1, 0 );

    # Overview per day
    my $DaysOfMonth = Days_in_Month( $Param{Year}, $Param{Month} );

    # get time accounting object
    my $TimeAccountingObject = $Kernel::OM->Get('Kernel::System::TimeAccounting');

    my %UserData = $TimeAccountingObject->UserGet(
        UserID => $Param{UserID},
    );

    for my $Day ( 1 .. $DaysOfMonth ) {
        $Param{Day} = sprintf( "%02d", $Day );
        $Param{Weekday} = Day_of_Week( $Param{Year}, $Param{Month}, $Day ) - 1;
        my $VacationCheck = $TimeObject->VacationCheck(
            Year     => $Param{Year},
            Month    => $Param{Month},
            Day      => $Day,
            Calendar => $UserData{Calendar},
        );

        my $Date = sprintf( "%04d-%02d-%02d", $Param{Year}, $Param{Month}, $Day );
        my $DayStartTime = $TimeObject->TimeStamp2SystemTime(
            String => $Date . ' 00:00:00',
        );
        my $DayStopTime = $TimeObject->TimeStamp2SystemTime(
            String => $Date . ' 23:59:59',
        );

        # add time zone to calculation
        my $UserCalendar = $UserData{Calendar} || '';
        my $Zone = $Kernel::OM->Get('Kernel::Config')->Get( "TimeZone::Calendar" . $UserCalendar );
        if ($Zone) {
            my $ZoneSeconds = $Zone * 60 * 60;
            $DayStartTime = $DayStartTime - $ZoneSeconds;
            $DayStopTime  = $DayStopTime - $ZoneSeconds;
        }

        my $ThisDayWorkingTime = $TimeObject->WorkingTime(
            StartTime => $DayStartTime,
            StopTime  => $DayStopTime,
            Calendar  => $UserCalendar,
        ) || '0';

        if ( $Param{Year} eq $Year && $Param{Month} eq $Month && $CurrentDay eq $Day ) {
            $Param{Class} = 'Active';
        }
        elsif ($VacationCheck) {
            $Param{Class}   = 'Vacation';
            $Param{Comment} = $VacationCheck;
        }
        elsif ($ThisDayWorkingTime) {
            $Param{Class} = 'WorkingDay';
        }
        else {
            $Param{Class} = 'NonWorkingDay';
        }

        my %Data = $TimeAccountingObject->WorkingUnitsGet(
            Year   => $Param{Year},
            Month  => $Param{Month},
            Day    => $Param{Day},
            UserID => $Param{UserID},
        );

        $Param{Comment} = $Data{Sick}
            ? Translatable('Sick leave')
            : $Data{LeaveDay} ? Translatable('On vacation')
            : $Data{Overtime} ? Translatable('On overtime leave')
            :                   '';

        $Param{WorkingHours} = $Data{Total} ? sprintf( "%.2f", $Data{Total} ) : '';

        $Param{Weekday_to_Text} = $WeekdayArray[ $Param{Weekday} ];
        $LayoutObject->Block(
            Name => 'Row',
            Data => {%Param},
        );
        $Param{Comment} = '';
    }

    my %UserReport = $TimeAccountingObject->UserReporting(
        Year  => $Param{Year},
        Month => $Param{Month},
    );
    for my $ReportElement (
        qw(TargetState TargetStateTotal WorkingHoursTotal WorkingHours
        Overtime OvertimeTotal OvertimeUntil LeaveDay LeaveDayTotal
        LeaveDayRemaining Sick SickTotal SickRemaining)
        )
    {
        $UserReport{ $Param{UserID} }{$ReportElement} ||= 0;
        $Param{$ReportElement} = sprintf( "%.2f", $UserReport{ $Param{UserID} }{$ReportElement} );
    }

    if ( $UserData{ShowOvertime} ) {
        $LayoutObject->Block(
            Name => 'Overtime',
            Data => \%Param,
        );
    }

    # Overview per project and action
    my %ProjectData = $TimeAccountingObject->ProjectActionReporting(
        Year   => $Param{Year},
        Month  => $Param{Month},
        UserID => $Param{UserID},
    );

    if ( IsHashRefWithData( \%ProjectData ) ) {

        # show the report sort by projects
        if ( !$Param{ProjectStatusShow} || $Param{ProjectStatusShow} eq 'valid' ) {
            $Param{ProjectStatusShow} = 'all';
        }
        elsif ( $Param{ProjectStatusShow} eq 'all' ) {
            $Param{ProjectStatusShow} = 'valid';
        }

        $Param{ShowProjects} = 'Show ' . $Param{ProjectStatusShow} . ' projects';

        $LayoutObject->Block(
            Name => 'ProjectTable',
            Data => {%Param},
        );

        PROJECTID:
        for my $ProjectID (
            sort { $ProjectData{$a}{Name} cmp $ProjectData{$b}{Name} } keys %ProjectData
            )
        {
            my $ProjectRef = $ProjectData{$ProjectID};
            my $ActionsRef = $ProjectRef->{Actions};

            $Param{Project} = '';
            $Param{Status} = $ProjectRef->{Status} ? '' : 'passiv';

            my $Total      = 0;
            my $TotalTotal = 0;

            next PROJECTID if $Param{ProjectStatusShow} eq 'all' && $Param{Status};

            if ($ActionsRef) {
                for my $ActionID (
                    sort { $ActionsRef->{$a}{Name} cmp $ActionsRef->{$b}{Name} }
                    keys %{$ActionsRef}
                    )
                {
                    my $ActionRef = $ActionsRef->{$ActionID};

                    $Param{Action}     = $ActionRef->{Name};
                    $Param{Hours}      = sprintf( "%.2f", $ActionRef->{PerMonth} || 0 );
                    $Param{HoursTotal} = sprintf( "%.2f", $ActionRef->{Total} || 0 );
                    $Total      += $Param{Hours};
                    $TotalTotal += $Param{HoursTotal};
                    $LayoutObject->Block(
                        Name => 'Action',
                        Data => {%Param},
                    );
                    if ( !$Param{Project} ) {
                        $Param{Project} = $ProjectRef->{Name};
                        my $ProjectDescription = $LayoutObject->Ascii2Html(
                            Text           => $ProjectRef->{Description},
                            HTMLResultMode => 1,
                            NewLine        => 50,
                        );

                        $LayoutObject->Block(
                            Name => 'Project',
                            Data => {
                                RowSpan => ( 1 + scalar keys %{$ActionsRef} ),
                                Status  => $Param{Status},
                            },
                        );

                        if ($ProjectDescription) {
                            $LayoutObject->Block(
                                Name => 'ProjectDescription',
                                Data => {
                                    ProjectDescription => $ProjectDescription,
                                },
                            );
                        }

                        if ( $UserData{CreateProject} ) {

                            # persons who are allowed to see the create object link are
                            # allowed to see the project reporting
                            $LayoutObject->Block(
                                Name => 'ProjectLink',
                                Data => {
                                    Project   => $ProjectRef->{Name},
                                    ProjectID => $ProjectID,
                                },
                            );
                        }
                        else {
                            $LayoutObject->Block(
                                Name => 'ProjectNoLink',
                                Data => { Project => $ProjectRef->{Name} },
                            );
                        }
                    }
                }

                # Now show row with total result of all actions of this project
                $Param{Hours}      = sprintf( "%.2f", $Total );
                $Param{HoursTotal} = sprintf( "%.2f", $TotalTotal );
                $Param{TotalHours}      += $Total;
                $Param{TotalHoursTotal} += $TotalTotal;
                $LayoutObject->Block(
                    Name => 'ActionTotal',
                    Data => {%Param},
                );
            }
        }
        if ( defined( $Param{TotalHours} ) ) {
            $Param{TotalHours} = sprintf( "%.2f", $Param{TotalHours} );
        }
        if ( defined( $Param{TotalHoursTotal} ) ) {
            $Param{TotalHoursTotal} = sprintf( "%.2f", $Param{TotalHoursTotal} );
        }
        $LayoutObject->Block(
            Name => 'GrandTotal',
            Data => {%Param},
        );
    }

    # build output
    my $Output = $LayoutObject->Header(
        Title => Translatable('Overview'),
    );
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        Data         => \%Param,
        TemplateFile => 'AgentTimeAccountingOverview'
    );
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _CheckValidityUserPeriods {
    my ( $Self, %Param ) = @_;

    my %Errors = ();
    my %GetParam;

    # get time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    for ( my $Period = 1; $Period <= $Param{Period}; $Period++ ) {

        # check for needed data
        for my $Parameter (qw(DateStart DateEnd LeaveDays)) {
            $GetParam{$Parameter}
                = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => $Parameter . "[$Period]" );
            if ( !$GetParam{$Parameter} ) {
                $Errors{ $Parameter . '-' . $Period . 'Invalid' }   = 'ServerError';
                $Errors{ $Parameter . '-' . $Period . 'ErrorType' } = 'MissingValue';
            }
        }
        my ( $Year, $Month, $Day ) = split( '-', $GetParam{DateStart} );
        my $StartDate = $TimeObject->Date2SystemTime(
            Year   => $Year,
            Month  => $Month,
            Day    => $Day,
            Hour   => 0,
            Minute => 0,
            Second => 0,
        );
        ( $Year, $Month, $Day ) = split( '-', $GetParam{DateEnd} );
        my $EndDate = $TimeObject->Date2SystemTime(
            Year   => $Year,
            Month  => $Month,
            Day    => $Day,
            Hour   => 0,
            Minute => 0,
            Second => 0,
        );
        if ( !$StartDate ) {
            $Errors{ 'DateStart-' . $Period . 'Invalid' }   = 'ServerError';
            $Errors{ 'DateStart-' . $Period . 'ErrorType' } = 'Invalid';
        }
        if ( !$EndDate ) {
            $Errors{ 'DateEnd-' . $Period . 'Invalid' }   = 'ServerError';
            $Errors{ 'DateEnd-' . $Period . 'ErrorType' } = 'Invalid';
        }
        if ( $StartDate && $EndDate && $StartDate >= $EndDate ) {
            $Errors{ 'DateEnd-' . $Period . 'Invalid' }   = 'ServerError';
            $Errors{ 'DateEnd-' . $Period . 'ErrorType' } = 'BeforeDateStart';
        }
    }

    return %Errors;
}

1;
