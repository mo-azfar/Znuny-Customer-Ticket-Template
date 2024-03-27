# --
# Copyright (C) 2024 mo-azfar, https://github.com/mo-azfar
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::FilterElementPost::CustomerTicketTemplate;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Queue',
    'Kernel::System::StandardTemplate',
    'Kernel::System::TemplateGenerator',
    'Kernel::System::Web::Request',
);

use Kernel::System::VariableCheck qw(:all);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ConfigObject            = $Kernel::OM->Get('Kernel::Config');
    my $ParamObject             = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $StandardTemplateObject  = $Kernel::OM->Get('Kernel::System::StandardTemplate');
    my $TemplateGeneratorObject = $Kernel::OM->Get('Kernel::System::TemplateGenerator');
    my $LayoutObject            = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $QueueObject             = $Kernel::OM->Get('Kernel::System::Queue');

    my $Action = $ParamObject->GetParam( Param => 'Action' );

    return 1 if !$Action;
    return 1 if !$Param{Templates}->{$Action};

    #get list of templates
    my %StandardTemplates = $StandardTemplateObject->StandardTemplateList(
        Valid => 1,
        Type  => 'Create',
    );

    return 1 if !%StandardTemplates;

    my $QueueEnabled = $ConfigObject->Get( 'Ticket::Frontend::' . $Action )->{Queue} || 0;

    my %AvailableValues;
    if ($QueueEnabled)
    {
        #check queue selection dropdown
        my @OptionValues = ${ $Param{Data} } =~ /<select[^>]*id="Dest"[^>]*>(.*?)<\/select>/s;

        QUEUES:
        while ( $OptionValues[0] =~ /<option.*?value="([^"]+)".*?>([^<]+)<\/option>/g )
        {
            my $DestID    = $1;
            my $QueueName = $2;
            my ( $QueueID, $QueueNames ) = split /\|\|/, $DestID;

            next QUEUES if $QueueID eq '';
            $AvailableValues{$QueueID} = $QueueName;
        }
    }
    else
    {
        my $QueueDefaultName = $ConfigObject->Get( 'Ticket::Frontend::' . $Action )->{QueueDefault} || 0;
        my $QueueDefaultID   = $QueueObject->QueueLookup( Queue => $QueueDefaultName );

        $AvailableValues{$QueueDefaultID} = $QueueDefaultName;
    }

    my %AvailableTemplates;

    TEMPLATES:
    for my $StandardTemplateID ( sort keys %StandardTemplates )
    {
        #get related queue
        my %RelatedQueues = $QueueObject->QueueStandardTemplateMemberList(
            StandardTemplateID => $StandardTemplateID,
        );

        #only get template that has relation to the queue
        next TEMPLATES if !%RelatedQueues;

        RELATED_QUEUE:
        for my $RelatedQueueID ( sort keys %RelatedQueues )
        {
            #only get template that available within queue selection dropdown
            if ( grep { $_ eq $RelatedQueueID } keys %AvailableValues )
            {
                #assign template id and queue dest (for preselect queue)
                $AvailableTemplates{$StandardTemplateID} = $RelatedQueueID . '||' . $RelatedQueues{$RelatedQueueID};
            }
            else
            {
                next RELATED_QUEUE;
            }
        }
    }

    return 1 if !%AvailableTemplates;

    my $TemplateCard = qq~ <div class="row-template"> ~;
    my $TemplateForm;
    my $JS;
    my $n = 1;

    for my $TemplateID ( sort keys %AvailableTemplates )
    {
        my %ThisTemplate = $StandardTemplateObject->StandardTemplateGet(
            ID => $TemplateID,
        );

        $TemplateCard .= qq~
        <div class="column-template">
            <div class="WidgetSimple WidgetSimpleTemplate" id="Template$n">
                <div class="Content" title="$ThisTemplate{Name}">
                    <p>$n. $ThisTemplate{Name}</p>
                </div>
            </div>
        </div>~;

        my $TemplateText = $TemplateGeneratorObject->Template(
            TemplateID => $TemplateID,
            UserID     => 1,
        );

        if ( $Param{AutoQueueSelected} eq 1 )
        {
            $JS .= qq~
                \$('#Template$n').on('click', function() {
                    if (\$('#Subject').val() != '') {
                        if (confirm('Setting a template will overwrite any text. Do you really want to continue?')) {
                            \$('#Dest').val('$AvailableTemplates{$TemplateID}').trigger('change');
                            \$('#Subject').val('$ThisTemplate{Name}');
                            CKEDITOR.instances.RichText.setData('$TemplateText');
                        }
                    }
                    else {
                        \$('#Dest').val('$AvailableTemplates{$TemplateID}').trigger('change');
                        \$('#Subject').val('$ThisTemplate{Name}');
                        CKEDITOR.instances.RichText.setData('$TemplateText');
                    }
                });
            ~;
        }
        else
        {
            $JS .= qq~
                \$('#Template$n').on('click', function() {
                    if (\$('#Subject').val() != '') {
                        if (confirm('Setting a template will overwrite any text. Do you really want to continue?')) {
                            \$('#Subject').val('$ThisTemplate{Name}');
                            CKEDITOR.instances.RichText.setData('$TemplateText');
                        }
                    }
                    else {
                        \$('#Subject').val('$ThisTemplate{Name}');
                        CKEDITOR.instances.RichText.setData('$TemplateText');
                    }
                });
            ~;
        }

        $n++;
    }
    $TemplateCard .= qq~ </div> ~;

    my $CSS = qq~<style type="text/css">
    .row-template {
        margin: 0 -0.313rem;
        display: flex;
        justify-content: center;
        flex-wrap: wrap;
        border-bottom: 0.1rem double #e8e8e8;
        margin-bottom: 0.3rem;
    }

    /* Clear floats after the columns */
    .row-template:after {
        content: "";
        display: table;
        clear: both;
    }

    .WidgetSimpleTemplate {
        cursor: pointer;
        border-color: #f92;
    }

    /* hover */
    .WidgetSimpleTemplate:hover {
        background: #f92;
    }

    /* Content text color */
    .WidgetSimpleTemplate .Content p {
        color: #251c17;
    }

    /* Float 4 columns side by side */
    .column-template {
        float: left;
        width: 25%;
        padding: 0 0.625rem;
        padding-bottom: 1.2rem;
    }

    \@media screen and (max-width: 600px) {
        .column-template {
            width: 100%;
            display: block;
            margin-bottom: 0.1rem;
        }
    </style>
    ~;

    my $SearchField1 = quotemeta "<fieldset class=\"TableLike card-item-wrapper\">";
    my $ReturnField1 = qq~ $CSS $TemplateCard
    <fieldset class="TableLike card-item-wrapper">
    ~;

    #search and replace
    ${ $Param{Data} } =~ s{$SearchField1}{$ReturnField1};

    #add jquery onclick block
    $LayoutObject->AddJSOnDocumentComplete(
        Code => $JS,
    );

    return 1;
}

1;
