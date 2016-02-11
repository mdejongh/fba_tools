package fba_tools::fba_toolsImpl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

=head1 NAME

fba_tools

=head1 DESCRIPTION

A KBase module: fba_tools
This module contains the implementation for the primary methods in KBase for metabolic model reconstruction, gapfilling, and analysis

=cut

#BEGIN_HEADER
use Bio::KBase::AuthToken;
use Bio::KBase::workspace::Client;
use Config::IniFiles;
use Data::Dumper;
use Bio::KBase::ObjectAPI::config;
use Bio::KBase::ObjectAPI::utilities;
use Bio::KBase::ObjectAPI::KBaseStore;
use Bio::KBase::ObjectAPI::logging;

#Initialization function for call
sub util_initialize_call {
	my ($self,$params,$ctx) = @_;
	print("Starting ".$ctx->method()." method.\n");
	delete($self->{_kbase_store});
	Bio::KBase::ObjectAPI::utilities::elaspedtime();
	Bio::KBase::ObjectAPI::config::username($ctx->user_id());
	Bio::KBase::ObjectAPI::config::token($ctx->token());
	Bio::KBase::ObjectAPI::config::provenance($ctx->provenance());
	return $params;
}

sub util_validate_args {
	my ($self,$params,$mandatoryArguments,$optionalArguments) = @_;
	print "Retrieving input parameters.\n";
	return Bio::KBase::ObjectAPI::utilities::ARGS($params,$mandatoryArguments,$optionalArguments);
}

sub util_kbase_store {
	my ($self) = @_;
    if (!defined($self->{_kbase_store})) {
    	my $wsClient=Bio::KBase::workspace::Client->new($self->{'workspace-url'},token => Bio::KBase::ObjectAPI::config::token());
    	$self->{_kbase_store} = Bio::KBase::ObjectAPI::KBaseStore->new({
			workspace => $wsClient
		});
    }
	return $self->{_kbase_store};
}

sub util_build_fba {
	my ($self,$params,$model,$media,$id,$add_external_reactions,$make_model_reactions_reversible,$source_model,$gapfilling) = @_;
	my $uptakelimits = {};
    if (defined($params->{max_c_uptake})) {
    	$uptakelimits->{C} = $params->{max_c_uptake}
    }
    if (defined($params->{max_n_uptake})) {
    	$uptakelimits->{N} = $params->{max_n_uptake}
    }
    if (defined($params->{max_p_uptake})) {
    	$uptakelimits->{P} = $params->{max_p_uptake}
    }
    if (defined($params->{max_s_uptake})) {
    	$uptakelimits->{S} = $params->{max_s_uptake}
    }
    if (defined($params->{max_o_uptake})) {
    	$uptakelimits->{O} = $params->{max_o_uptake}
    }
    my $exp_matrix;
	my $exphash = {};
    if (defined($params->{expseries_id})) {
    	print "Retrieving expression matrix.\n";
    	$exp_matrix = $self->util_kbase_store()->get_object($params->{expseries_workspace}."/".$params->{expseries_id});
    	if (!defined($params->{exp_condition})) {
			Bio::KBase::ObjectAPI::utilities::error("Input must specify the column to select from the expression matrix");
		}
		
    	my $float_matrix = $exp_matrix->{data};
	    my $exp_sample_col = -1;
	    for (my $i=0; $i < @{$float_matrix->{"col_ids"}}; $i++) {
			if ($float_matrix->{col_ids}->[$i] eq $params->{exp_condition}) {
			    $exp_sample_col = $i;
			    last;
			}
	    }
	    if ($exp_sample_col < 0) {
			Bio::KBase::ObjectAPI::utilities::error("No column named ".$params->{exp_condition}." in expression matrix.");
	    }
	    for (my $i=0; $i < @{$float_matrix->{row_ids}}; $i++) {
			$exphash->{$float_matrix->{row_ids}->[$i]} = $float_matrix->{values}->[$i]->[$exp_sample_col];
	    }
    }
    my $fbaobj = Bio::KBase::ObjectAPI::KBaseFBA::FBA->new({
		id => $id,
		fva => defined $params->{fva} ? $params->{fva} : 0,
		fluxMinimization => defined $params->{minimize_flux} ? $params->{minimize_flux} : 0,
		findMinimalMedia => defined $params->{find_min_media} ? $params->{find_min_media} : 0,
		allReversible => defined $params->{all_reversible} ? $params->{all_reversible} : 0,
		simpleThermoConstraints => defined $params->{thermodynamic_constraints} ? $params->{thermodynamic_constraints} : 0,
		thermodynamicConstraints => defined $params->{thermodynamic_constraints} ? $params->{thermodynamic_constraints} : 0,
		noErrorThermodynamicConstraints => 0,
		minimizeErrorThermodynamicConstraints => 0,
		maximizeObjective => 1,
		compoundflux_objterms => {},
    	reactionflux_objterms => {},
		biomassflux_objterms => {},
		comboDeletions => defined $params->{simulate_ko} ? $params->{simulate_ko} : 0,
		numberOfSolutions => defined $params->{number_of_solutions} ? $params->{number_of_solutions} : 1,
		objectiveConstraintFraction => defined $params->{objective_fraction} ? $params->{objective_fraction} : 0.1,
		defaultMaxFlux => 1000,
		defaultMaxDrainFlux => defined $params->{default_max_uptake} ? $params->{default_max_uptake} : 0,
		defaultMinDrainFlux => -1000,
		decomposeReversibleFlux => 0,
		decomposeReversibleDrainFlux => 0,
		fluxUseVariables => 0,
		drainfluxUseVariables => 0,
		fbamodel => $model,
		fbamodel_ref => $model->_reference(),
		media => $media,
		media_ref => $media->_reference(),
		geneKO_refs => [],
		reactionKO_refs => [],
		additionalCpd_refs => [],
		uptakeLimits => $uptakelimits,
		parameters => {},
		inputfiles => {},
		FBAConstraints => [],
		FBAReactionBounds => [],
		FBACompoundBounds => [],
		outputfiles => {},
		FBACompoundVariables => [],
		FBAReactionVariables => [],
		FBABiomassVariables => [],
		FBAPromResults => [],
		FBADeletionResults => [],
		FBAMinimalMediaResults => [],
		FBAMetaboliteProductionResults => [],
		massbalance => "",
		ExpressionAlpha => defined $params->{activation_coefficient} ? $params->{activation_coefficient} : 0.5,
		ExpressionOmega => defined $params->{omega} ? $params->{omega} : 0,
		ExpressionKappa => defined $params->{exp_threshold_margin} ? $params->{exp_threshold_margin} : 0.1
	});
	$fbaobj->parent($self->util_kbase_store());
	$fbaobj->parameters()->{minimum_target_flux} = defined $params->{minimum_target_flux} ? $params->{minimum_target_flux} : 0.01;
	if (!defined($params->{target_reaction})) {
		$params->{target_reaction} = "bio1";
	}
    my $bio = $model->searchForBiomass($params->{target_reaction});
	if (defined($bio)) {
		$fbaobj->biomassflux_objterms()->{$bio->id()} = 1;
	} else {
		my $rxn = $model->searchForReaction($params->{target_reaction});
		if (defined($rxn)) {
			$fbaobj->reactionflux_objterms()->{$rxn->id()} = 1;
		} else {
			my $cpd = $model->searchForCompound($params->{target_reaction});
			if (defined($cpd)) {
				$fbaobj->compoundflux_objterms()->{$cpd->id()} = 1;
			}
		}
	}
	if (!defined($params->{custom_bound_list})) {
		$params->{custom_bound_list} = [];
	}
	for (my $i=0; $i < @{$params->{custom_bound_list}}; $i++) {
		my $array = [split(/[\<;]/,$params->{custom_bound_list}->[$i])];
		my $rxn = $model->searchForReaction($array->[1]);
		if (defined($rxn)) {
			$fbaobj->add("FBAReactionBounds",{
				modelreaction_ref => $rxn->_reference(),
				variableType => "flux",
				upperBound => $array->[2]+0,
				lowerBound => $array->[0]+0
			});
		} else {
			my $cpd = $model->searchForCompound($array->[1]);
			if (defined($cpd)) {
				$fbaobj->add("FBACompoundBounds",{
					modelcompound_ref => $cpd->_reference(),
					variableType => "drainflux",
					upperBound => $array->[2]+0,
					lowerBound => $array->[0]+0
				});
			}
		}
	}
    if (defined($exp_matrix) || (defined($gapfilling) && $gapfilling == 1)) {
		if ($params->{minimum_target_flux} < 0.1) {
			$params->{minimum_target_flux} = 0.1;
		}
		if (!defined($exp_matrix) && $params->{comprehensive_gapfill} == 0) {
			$params->{activation_coefficient} = 0;
		}
		my $input = {
			minimum_target_flux => $params->{minimum_target_flux},
			target_reactions => [],#?
			completeGapfill => 0,#?
			fastgapfill => 1,
			alpha => $params->{activation_coefficient},
			omega => $params->{omega},
			num_solutions => $params->{number_of_solutions},
			add_external_rxns => $add_external_reactions,
			make_model_rxns_reversible => $make_model_reactions_reversible,
			activate_all_model_reactions => 0,
		};
		if (defined($exp_matrix)) {
			$input->{expsample} = $exphash;
			$input->{expression_threshold_percentile} = $params->{exp_threshold_percentile};
			$input->{kappa} = $params->{exp_threshold_margin};
			$fbaobj->expression_matrix_ref($params->{expseries_workspace}."/".$params->{expseries_id});
			$fbaobj->expression_matrix_column($params->{exp_condition});	
		}
		if (defined($source_model)) {
    		$input->{source_model} = $source_model;
    	}
		$fbaobj->PrepareForGapfilling($input);
    }
    return $fbaobj;
}

sub func_build_metabolic_model {
	my ($self,$params) = @_;
	$params = $self->util_validate_args($params,["workspace","genome_id"],{
    	media_id => undef,
    	template_id => undef,
    	genome_workspace => $params->{workspace},
    	template_workspace => $params->{workspace},
    	media_workspace => $params->{workspace},
    	fbamodel_output_id => $params->{genome_id}.".model",
    	coremodel => 0,
    	gapfill_model => 1,
    	thermodynamic_constraints => 0,
    	comprehensive_gapfill => 0,
    	custom_bound_list => [],
		media_supplement_list => [],
		expseries_id => undef,
		expseries_workspace => $params->{workspace},
		exp_condition => undef,
		exp_threshold_percentile => 0.5,
		exp_threshold_margin => 0.1,
		activation_coefficient => 0.5,
		omega => 0,
		objective_fraction => 0.1,
		minimum_target_flux => 0.1,
		number_of_solutions => 1
    });
	#Getting genome
	print "Retrieving genome.\n";
	my $genome = $self->util_kbase_store()->get_object($params->{genome_workspace}."/".$params->{genome_id});
	#Classifying genome
	if (!defined($params->{template_id})) {
    	print "Classifying genome in order to select template.\n";
    	$params->{template_workspace} = "NewKBaseModelTemplates";
    	if ($genome->template_classification() eq "plant") {
    		$params->{template_id} = "PlantModelTemplate";
    	} elsif ($genome->template_classification() eq "Gram negative") {
    		$params->{template_id} = "GramNegModelTemplate";
    	} elsif ($genome->template_classification() eq "Gram positive") {
    		$params->{template_id} = "GramPosModelTemplate";
    	}
	}
    #Retrieving template
    print "Retrieving model template ".$params->{template_id}.".\n";
    my $template = $self->util_kbase_store()->get_object($params->{template_workspace}."/".$params->{template_id});
    #Building the model
    my $model = $template->buildModel({
	    genome => $genome,
	    modelid => $params->{fbamodel_output_id},
	    fulldb => 0
	});
	#Gapfilling model if requested
	my $output;
	if ($params->{gapfill_model} == 1) {
		$output = $self->func_gapfill_metabolic_model({
			thermodynamic_constraints => $params->{thermodynamic_constraints},
	    	comprehensive_gapfill => $params->{comprehensive_gapfill},
	    	custom_bound_list => $params->{custom_bound_list},
			media_supplement_list => $params->{media_supplement_list},
			expseries_id => $params->{expseries_id},
			expseries_workspace => $params->{expseries_workspace},
			exp_condition => $params->{exp_condition},
			exp_threshold_percentile => $params->{exp_threshold_percentile},
			exp_threshold_margin => $params->{exp_threshold_margin},
			activation_coefficient => $params->{activation_coefficient},
			omega => $params->{omega},
			objective_fraction => $params->{objective_fraction},
			minimum_target_flux => $params->{minimum_target_flux},
			number_of_solutions => $params->{number_of_solutions},
			workspace => $params->{workspace},
			fbamodel_id => $params->{fbamodel_output_id},
			fbamodel_output_id => $params->{fbamodel_output_id},
			media_workspace => $params->{media_workspace},
			media_id => $params->{media_id}
		},$model);
	} else {
		#If not gapfilling, then we just save the model directly
		$output->{number_gapfilled_reactions} = 0;
		$output->{number_removed_biomass_compounds} = 0;
		my $wsmeta = $self->util_kbase_store()->save_object($model,$params->{workspace}."/".$params->{fbamodel_output_id});
		$output->{new_fbamodel_ref} = $params->{workspace}."/".$params->{fbamodel_output_id};
	}
	return $output;
}

sub func_gapfill_metabolic_model {
	my ($self,$params,$model) = @_;
	$params = $self->util_validate_args($params,["workspace","fbamodel_id"],{
    	fbamodel_workspace => $params->{workspace},
    	media_id => undef,
    	media_workspace => $params->{workspace},
    	target_reaction => "bio1",
    	fbamodel_output_id => $params->{fbamodel_id},
    	thermodynamic_constraints => 0,
    	comprehensive_gapfill => 0,
    	source_fbamodel_id => undef,
    	source_fbamodel_workspace => $params->{workspace},
    	feature_ko_list => [],
		reaction_ko_list => [],
		custom_bound_list => [],
		media_supplement_list => [],
		expseries_id => undef,
    	expseries_workspace => $params->{workspace},
    	exp_condition => undef,
    	exp_threshold_percentile => 0.5,
    	exp_threshold_margin => 0.1,
    	activation_coefficient => 0.5,
    	omega => 0,
    	objective_fraction => 0,
    	minimum_target_flux => 0.1,
		number_of_solutions => 1
    });
    if (!defined($model)) {
    	print "Retrieving model.\n";
		$model = $self->util_kbase_store()->get_object($params->{fbamodel_workspace}."/".$params->{fbamodel_id});
    }
    if (!defined($params->{media_id})) {
    	$params->{media_id} = "Complete";
    	$params->{media_workspace} = "KBaseMedia";
    }
    print "Retrieving ".$params->{media_id}." media.\n";
    my $media = $self->util_kbase_store()->get_object($params->{media_workspace}."/".$params->{media_id});
    print "Preparing flux balance analysis problem.\n";
    my $source_model;
    if (defined($params->{source_fbamodel_id})) {
		$source_model = $self->util_kbase_store()->get_object($params->{source_fbamodel_workspace}."/".$params->{source_fbamodel_id});
	}
	my $gfs = $model->gapfillings();
	my $currentid = 0;
	for (my $i=0; $i < @{$gfs}; $i++) {
		if ($gfs->[$i]->id() =~ m/gf\.(\d+)$/) {
			if ($1 >= $currentid) {
				$currentid = $1+1;
			}
		}
	}
	my $gfid = "gf.".$currentid;
    my $fba = $self->util_build_fba($params,$model,$media,$params->{fbamodel_output_id}.".".$gfid,1,1,$source_model,1);
    print "Running flux balance analysis problem.\n";
	$fba->runFBA();
	#Error checking the FBA and gapfilling solution
	$fba->parseGapfillingOutput();
	if (!defined($fba->gapfillingSolutions()->[0])) {
		Bio::KBase::ObjectAPI::utilities::error("Analysis completed, but no valid solutions found!");
	}
	$model->add_gapfilling({
		object => $fba,
		id => $gfid,
		solution_to_integrate => "0"
	});
    print "Saving gapfilled model.\n";
    my $wsmeta = $self->util_kbase_store()->save_object($model,$params->{workspace}."/".$params->{fbamodel_output_id});
    print "Saving FBA object with gapfilling sensitivity analysis and flux.\n";
    $fba->fbamodel_ref($model->_reference());
    $wsmeta = $self->util_kbase_store()->save_object($fba,$params->{workspace}."/".$params->{fbamodel_output_id}.".".$gfid);
	return {
		new_fba_ref => $params->{workspace}."/".$params->{fbamodel_output_id}.".".$gfid,
		new_fbamodel_ref => $params->{workspace}."/".$params->{fbamodel_output_id},
		number_gapfilled_reactions => 0,
		number_removed_biomass_compounds => 0
	};
}

sub func_run_flux_balance_analysis {
	my ($self,$params,$model) = @_;
	$params = $self->util_validate_args($params,["workspace","fbamodel_id","fba_output_id"],{
		fbamodel_workspace => $params->{workspace},
		media_id => undef,
		media_workspace => $params->{workspace},
		target_reaction => "bio1",
		thermodynamic_constraints => 0,
		fva => 0,
		minimize_flux => 0,
		simulate_ko => 0,
		find_min_media => 0,
		all_reversible => 0,
		feature_ko_list => [],
		reaction_ko_list => [],
		custom_bound_list => [],
		media_supplement_list => [],
		expseries_id => undef,
		expseries_workspace => $params->{workspace},
		exp_condition => undef,
		exp_threshold_percentile => 0.5,
		exp_threshold_margin => 0.1,
		activation_coefficient => 0.5,
		omega => 0,
		objective_fraction => 0.1,
		max_c_uptake => undef,
		max_n_uptake => undef,
		max_p_uptake => undef,
		max_s_uptake => undef,
		max_o_uptake => undef,
		default_max_uptake => 1000,
		notes => undef,
		massbalance => undef
    });
    if (!defined($model)) {
    	print "Retrieving model.\n";
		$model = $self->util_kbase_store()->get_object($params->{fbamodel_workspace}."/".$params->{fbamodel_id});
    }
    my $expseries;
    if (defined($params->{expseries_id})) {
    	print "Retrieving expression matrix.\n";
    	$expseries = $self->util_kbase_store()->get_object($params->{expseries_workspace}."/".$params->{expseries_id});
    }
    if (!defined($params->{media_id})) {
    	$params->{media_id} = "Complete";
    	$params->{media_workspace} = "KBaseMedia";
    }
    print "Retrieving ".$params->{media_id}." media.\n";
    my $media = $self->util_kbase_store()->get_object($params->{media_workspace}."/".$params->{media_id});
    print "Preparing flux balance analysis problem.\n";
    my $fba = $self->util_build_fba($params,$model,$media,$params->{fba_output_id},0,0,undef);
    #Running FBA
    print "Running flux balance analysis problem.\n";
    my $objective;
    eval {
		local $SIG{ALRM} = sub { die "FBA timed out! Model likely contains numerical instability!" };
		alarm 3600;
		$objective = $fba->runFBA();
		alarm 0;
	};
    if (!defined($objective)) {
    	Bio::KBase::ObjectAPI::utilities::error("FBA failed with no solution returned!");
    }    
    print "Saving FBA results.\n";
    my $wsmeta = $self->util_kbase_store()->save_object($model,$params->{workspace}."/".$params->{fba_output_id});
	return {
		new_fba_ref => $params->{workspace}."/".$params->{fba_output_id}
	};
}

sub func_compare_fba_solutions {
	my ($self,$params) = @_;
	$params = $self->util_validate_args($params,["workspace","fba_id_list","fbacomparison_output_id"],{
		fba_workspace => $params->{workspace},
    });
    my $fbacomp = Bio::KBase::ObjectAPI::KBaseFBA::FBAComparison->new({
    	id => $params->{fbacomparison_output_id},
    	common_reactions => 0,
    	common_compounds => 0,
    	fbas => [],
    	reactions => [],
    	compounds => []
    });
    $fbacomp->parent($self->util_kbase_store());
    my $commoncompounds = 0;
    my $commonreactions = 0;
    my $fbahash = {};
    my $fbaids = [];
    my $fbarxns = {};
    my $rxnhash = {};
    my $cpdhash = {};
    my $fbacpds = {};
    my $fbacount = @{$params->{fba_id_list}};
    for (my $i=0; $i < @{$params->{fba_id_list}}; $i++) {
    	$fbaids->[$i] = $params->{fba_workspace}."/".$params->{fba_id_list}->[$i];
    	print "Retrieving FBA ".$fbaids->[$i].".\n";
    	my $fba = $self->util_kbase_store()->get_object($fbaids->[$i]);
   		my $rxns = $fba->FBAReactionVariables();
		my $cpds = $fba->FBACompoundVariables();
		my $cpdcount = @{$cpds};
		my $rxncount = @{$rxns};
		$fbahash->{$fbaids->[$i]} = $fbacomp->add("fbas",{
			id => $fbaids->[$i],
			fba_ref => $fba->_reference(),
			fbamodel_ref => $fba->fbamodel_ref(),
			fba_similarity => {},
			objective => $fba->objectiveValue(),
			media_ref => $fba->media_ref(),
			reactions => $rxncount,
			compounds => $cpdcount,
			forward_reactions => 0,
			reverse_reactions => 0,
			uptake_compounds => 0,
			excretion_compounds => 0
		});
		my $forwardrxn = 0;
		my $reverserxn = 0;
		my $uptakecpd = 0;
		my $excretecpd = 0;
		for (my $j=0; $j < @{$rxns}; $j++) {
			my $id = $rxns->[$j]->modelreaction()->reaction()->id();
			my $name = $rxns->[$j]->modelreaction()->reaction()->name();
			if ($id eq "rxn00000") {
				$id = $rxns->[$j]->modelreaction()->id();
				$name = $rxns->[$j]->modelreaction()->id();
			} elsif ($rxns->[$j]->modelreaction()->id() =~ m/_([a-z]+\d+)$/) {
				$id .= "_".$1;
			}
			if (!defined($rxnhash->{$id})) {
				$rxnhash->{$id} = $fbacomp->add("reactions",{
					id => $id,
					name => $name,
					stoichiometry => $rxns->[$j]->modelreaction()->stoichiometry(),
					direction => $rxns->[$j]->modelreaction()->direction(),
					state_conservation => {},
					most_common_state => "unknown",
					reaction_fluxes => {}
				});
			}
			my $state = "IA";
			if ($rxns->[$j]->value() > 0.000000001) {
				$state = "FOR";
				$forwardrxn++;
			} elsif ($rxns->[$j]->value() < -0.000000001) {
				$state = "REV";
				$reverserxn++;
			}
			if (!defined($rxnhash->{$id}->state_conservation()->{$state})) {
				$rxnhash->{$id}->state_conservation()->{$state} = [0,0,0,0];
			}
			$rxnhash->{$id}->state_conservation()->{$state}->[0]++;
			$rxnhash->{$id}->state_conservation()->{$state}->[2] += $rxns->[$j]->value();
			$rxnhash->{$id}->reaction_fluxes()->{$fbaids->[$i]} = [$state,$rxns->[$j]->upperBound(),$rxns->[$j]->lowerBound(),$rxns->[$j]->max(),$rxns->[$j]->min(),$rxns->[$j]->value(),$rxns->[$j]->scaled_exp(),$rxns->[$j]->exp_state(),$rxns->[$j]->modelreaction()->id()];
			$fbarxns->{$fbaids->[$i]}->{$id} = $state;
		}
		for (my $j=0; $j < @{$cpds}; $j++) {
			my $id = $cpds->[$j]->modelcompound()->id();
			if (!defined($cpdhash->{$id})) {
				$cpdhash->{$id} = $fbacomp->add("compounds",{
					id => $id,
					name => $cpds->[$j]->modelcompound()->name(),
					charge => $cpds->[$j]->modelcompound()->charge(),
					formula => $cpds->[$j]->modelcompound()->formula(),
					state_conservation => {},
					most_common_state => "unknown",
					exchanges => {}
				});
			}
			my $state = "IA";
			if ($cpds->[$j]->value() > 0.000000001) {
				$state = "UP";
				$uptakecpd++;
			} elsif ($cpds->[$j]->value() < -0.000000001) {
				$state = "EX";
				$excretecpd++;
			}
			if (!defined($cpdhash->{$id}->state_conservation()->{$state})) {
				$cpdhash->{$id}->state_conservation()->{$state} = [0,0,0,0];
			}
			$cpdhash->{$id}->state_conservation()->{$state}->[0]++;
			$cpdhash->{$id}->state_conservation()->{$state}->[2] += $cpds->[$j]->value();
			$cpdhash->{$id}->exchanges()->{$fbaids->[$i]} = [$state,$cpds->[$j]->upperBound(),$cpds->[$j]->lowerBound(),$cpds->[$j]->max(),$cpds->[$j]->min(),$cpds->[$j]->value(),$cpds->[$j]->class()];
			$fbacpds->{$fbaids->[$i]}->{$id} = $state;
		}
		foreach my $comprxn (keys(%{$rxnhash})) {
			if (!defined($rxnhash->{$comprxn}->reaction_fluxes()->{$fbaids->[$i]})) {
				if (!defined($rxnhash->{$comprxn}->state_conservation()->{NA})) {
					$rxnhash->{$comprxn}->state_conservation()->{NA} = [0,0,0,0];
				}
				$rxnhash->{$comprxn}->state_conservation()->{NA}->[0]++;
			}
		}
		foreach my $compcpd (keys(%{$cpdhash})) {
			if (!defined($cpdhash->{$compcpd}->exchanges()->{$fbaids->[$i]})) {
				if (!defined($cpdhash->{$compcpd}->state_conservation()->{NA})) {
					$cpdhash->{$compcpd}->state_conservation()->{NA} = [0,0,0,0];
				}
				$cpdhash->{$compcpd}->state_conservation()->{NA}->[0]++;
			}
		}
		$fbahash->{$fbaids->[$i]}->forward_reactions($forwardrxn);
		$fbahash->{$fbaids->[$i]}->reverse_reactions($reverserxn);
		$fbahash->{$fbaids->[$i]}->uptake_compounds($uptakecpd);
		$fbahash->{$fbaids->[$i]}->excretion_compounds($excretecpd);
    }
    print "Computing similarities.\n";
    for (my $i=0; $i < @{$fbaids}; $i++) {
    	for (my $j=0; $j < @{$fbaids}; $j++) {
    		if ($j != $i) {
    			$fbahash->{$fbaids->[$i]}->fba_similarity()->{$fbaids->[$j]} = [0,0,0,0,0,0];
    		}
    	}
    }
    print "Comparing reaction states.\n";
    foreach my $rxn (keys(%{$rxnhash})) {
    	my $fbalist = [keys(%{$rxnhash->{$rxn}->reaction_fluxes()})];
    	my $rxnfbacount = @{$fbalist};
    	foreach my $state (keys(%{$rxnhash->{$rxn}->state_conservation()})) {
    		$rxnhash->{$rxn}->state_conservation()->{$state}->[1] = $rxnhash->{$rxn}->state_conservation()->{$state}->[0]/$fbacount;
			$rxnhash->{$rxn}->state_conservation()->{$state}->[2] = $rxnhash->{$rxn}->state_conservation()->{$state}->[2]/$rxnhash->{$rxn}->state_conservation()->{$state}->[0];
    	}
    	for (my $i=0; $i < @{$fbalist}; $i++) {
    		my $item = $rxnhash->{$rxn}->reaction_fluxes()->{$fbalist->[$i]};
    		my $diff = $item->[5]-$rxnhash->{$rxn}->state_conservation()->{$item->[0]}->[2];
    		$rxnhash->{$rxn}->state_conservation()->{$item->[0]}->[3] += ($diff*$diff);
    		for (my $j=0; $j < @{$fbalist}; $j++) {
    			if ($j != $i) {
    				$fbahash->{$fbalist->[$i]}->fba_similarity()->{$fbalist->[$j]}->[0]++;
    				if ($rxnhash->{$rxn}->reaction_fluxes()->{$fbalist->[$i]}->[5] < -0.00000001 && $rxnhash->{$rxn}->reaction_fluxes()->{$fbalist->[$j]}->[5] < -0.00000001) {
    					$fbahash->{$fbalist->[$i]}->fba_similarity()->{$fbalist->[$j]}->[2]++;
    				}
    				if ($rxnhash->{$rxn}->reaction_fluxes()->{$fbalist->[$i]}->[5] > 0.00000001 && $rxnhash->{$rxn}->reaction_fluxes()->{$fbalist->[$j]}->[5] > 0.00000001) {
    					$fbahash->{$fbalist->[$i]}->fba_similarity()->{$fbalist->[$j]}->[1]++;
    				}
    				if ($rxnhash->{$rxn}->reaction_fluxes()->{$fbalist->[$i]}->[5] == 0 && $rxnhash->{$rxn}->reaction_fluxes()->{$fbalist->[$j]}->[5] == 0) {
    					$fbahash->{$fbalist->[$i]}->fba_similarity()->{$fbalist->[$j]}->[3]++;
    				}
    			}	
    		}
    	}
    	my $bestcount = 0;
    	my $beststate;
    	foreach my $state (keys(%{$rxnhash->{$rxn}->state_conservation()})) {
    		$rxnhash->{$rxn}->state_conservation()->{$state}->[3] = $rxnhash->{$rxn}->state_conservation()->{$state}->[3]/$rxnhash->{$rxn}->state_conservation()->{$state}->[0];
    		$rxnhash->{$rxn}->state_conservation()->{$state}->[3] = sqrt($rxnhash->{$rxn}->state_conservation()->{$state}->[3]);
    		if ($rxnhash->{$rxn}->state_conservation()->{$state}->[0] > $bestcount) {
    			$bestcount = $rxnhash->{$rxn}->state_conservation()->{$state}->[0];
    			$beststate = $state;
    		}
    	}
    	$rxnhash->{$rxn}->most_common_state($beststate);
    	if ($rxnfbacount == $fbacount) {
    		$commonreactions++;
    	}
    }
    print "Comparing compound states.\n";
    foreach my $cpd (keys(%{$cpdhash})) {
    	my $fbalist = [keys(%{$cpdhash->{$cpd}->exchanges()})];
    	my $cpdfbacount = @{$fbalist};
    	foreach my $state (keys(%{$cpdhash->{$cpd}->state_conservation()})) {
    		$cpdhash->{$cpd}->state_conservation()->{$state}->[1] = $cpdhash->{$cpd}->state_conservation()->{$state}->[0]/$fbacount;
			$cpdhash->{$cpd}->state_conservation()->{$state}->[2] = $cpdhash->{$cpd}->state_conservation()->{$state}->[2]/$cpdhash->{$cpd}->state_conservation()->{$state}->[0];
    	}
    	for (my $i=0; $i < @{$fbalist}; $i++) {
    		my $item = $cpdhash->{$cpd}->exchanges()->{$fbalist->[$i]};
    		my $diff = $item->[5]-$cpdhash->{$cpd}->state_conservation()->{$item->[0]}->[2];
    		$cpdhash->{$cpd}->state_conservation()->{$item->[0]}->[3] += ($diff*$diff);
    		for (my $j=0; $j < @{$fbalist}; $j++) {
    			if ($j != $i) {
    				$fbahash->{$fbalist->[$i]}->fba_similarity()->{$fbalist->[$j]}->[4]++;
    				if ($cpdhash->{$cpd}->exchanges()->{$fbalist->[$i]}->[5] < -0.00000001 && $cpdhash->{$cpd}->exchanges()->{$fbalist->[$j]}->[5] < -0.00000001) {
    					$fbahash->{$fbalist->[$i]}->fba_similarity()->{$fbalist->[$j]}->[6]++;
    				}
    				if ($cpdhash->{$cpd}->exchanges()->{$fbalist->[$i]}->[5] > 0.00000001 && $cpdhash->{$cpd}->exchanges()->{$fbalist->[$j]}->[5] > 0.00000001) {
    					$fbahash->{$fbalist->[$i]}->fba_similarity()->{$fbalist->[$j]}->[5]++;
    				}
    				if ($cpdhash->{$cpd}->exchanges()->{$fbalist->[$i]}->[5] == 0 && $cpdhash->{$cpd}->exchanges()->{$fbalist->[$j]}->[5] == 0) {
    					$fbahash->{$fbalist->[$i]}->fba_similarity()->{$fbalist->[$j]}->[7]++;
    				}
    			}	
    		}
    	}
    	my $bestcount = 0;
    	my $beststate;
    	foreach my $state (keys(%{$cpdhash->{$cpd}->state_conservation()})) {
    		$cpdhash->{$cpd}->state_conservation()->{$state}->[3] = $cpdhash->{$cpd}->state_conservation()->{$state}->[3]/$cpdhash->{$cpd}->state_conservation()->{$state}->[0];
    		$cpdhash->{$cpd}->state_conservation()->{$state}->[3] = sqrt($cpdhash->{$cpd}->state_conservation()->{$state}->[3]);
    		if ($cpdhash->{$cpd}->state_conservation()->{$state}->[0] > $bestcount) {
    			$bestcount = $cpdhash->{$cpd}->state_conservation()->{$state}->[0];
    			$beststate = $state;
    		}
    	}
    	$cpdhash->{$cpd}->most_common_state($beststate);
    	if ($cpdfbacount == $fbacount) {
    		$commoncompounds++;
    	}
    }
    $fbacomp->common_compounds($commoncompounds);
    $fbacomp->common_reactions($commonreactions);
    print "Saving FBA comparison object.\n";
    my $wsmeta = $self->util_kbase_store()->save_object($fbacomp,$params->{workspace}."/".$params->{fbacomparison_output_id});
	return {
		new_fbacomparison_ref => $params->{workspace}."/".$params->{fbacomparison_output_id}
	};
}

sub func_propagate_model_to_new_genome {
	my ($self,$params) = @_;
    $params = $self->util_validate_args($params,["workspace","fbamodel_id","proteincomparison_id","fbamodel_output_id"],{
    	fbamodel_workspace => $params->{workspace},
    	proteincomparison_workspace => $params->{workspace},
    	keep_nogene_rxn => 0,
    	gapfill_model => 0,
    	media_id => undef,
    	media_workspace => $params->{workspace},
    	thermodynamic_constraints => 0,
    	comprehensive_gapfill => 0,
    	custom_bound_list => [],
		media_supplement_list => [],
		expseries_id => undef,
		expseries_workspace => $params->{workspace},
		exp_condition => undef,
		exp_threshold_percentile => 0.5,
		exp_threshold_margin => 0.1,
		activation_coefficient => 0.5,
		omega => 0,
		objective_fraction => 0.1,
		minimum_target_flux => 0.1,
		number_of_solutions => 1
    });
	#Getting genome
	print "Retrieving model.\n";
	my $model = $self->util_kbase_store()->get_object($params->{fbamodel_workspace}."/".$params->{fbamodel_id});
	print "Retrieving proteome comparison.\n";
	my $protcomp = $self->util_kbase_store()->get_object($params->{proteincomparison_workspace}."/".$params->{proteincomparison_id});
	print "Translating model.\n";
	my $report = $model->translate_model({
		proteome_comparison => $protcomp,
		keep_nogene_rxn => $params->{keep_nogene_rxn}
	});
	#Gapfilling model if requested
	my $output;
	if ($params->{gapfill_model} == 1) {
		$output = $self->func_gapfill_metabolic_model({
			thermodynamic_constraints => $params->{thermodynamic_constraints},
	    	comprehensive_gapfill => $params->{comprehensive_gapfill},
	    	custom_bound_list => $params->{custom_bound_list},
			media_supplement_list => $params->{media_supplement_list},
			expseries_id => $params->{expseries_id},
			expseries_workspace => $params->{expseries_workspace},
			exp_condition => $params->{exp_condition},
			exp_threshold_percentile => $params->{exp_threshold_percentile},
			exp_threshold_margin => $params->{exp_threshold_margin},
			activation_coefficient => $params->{activation_coefficient},
			omega => $params->{omega},
			objective_fraction => $params->{objective_fraction},
			minimum_target_flux => $params->{minimum_target_flux},
			number_of_solutions => $params->{number_of_solutions},
			workspace => $params->{workspace},
			fbamodel_id => $params->{fbamodel_output_id},
			fbamodel_output_id => $params->{fbamodel_output_id},
			media_workspace => $params->{media_workspace},
			media_id => $params->{media_id}
		},$model);
	} else {
		#If not gapfilling, then we just save the model directly
		$output->{number_gapfilled_reactions} = 0;
		$output->{number_removed_biomass_compounds} = 0;
		my $wsmeta = $self->util_kbase_store()->save_object($model,$params->{workspace}."/".$params->{fbamodel_output_id});
		$output->{new_fbamodel_ref} = $params->{workspace}."/".$params->{fbamodel_output_id};
	}
	return $output;
}

sub func_simulate_growth_on_phenotype_data {
	my ($self,$params,$model) = @_;
	$params = $self->util_validate_args($params,["workspace","fbamodel_id","phenotypeset_id","phenotypesim_output_id"],{
		fbamodel_workspace => $params->{workspace},
		phenotypeset_workspace => $params->{workspace},
		thermodynamic_constraints => 0,
		all_reversible => 0,
		feature_ko_list => [],
		reaction_ko_list => [],
		custom_bound_list => [],
		media_supplement_list => []
    });
    if (!defined($model)) {
    	print "Retrieving model.\n";
		$model = $self->util_kbase_store()->get_object($params->{fbamodel_workspace}."/".$params->{fbamodel_id});
    }
    my $expseries;
    if (defined($params->{expseries_id})) {
    	print "Retrieving expression matrix.\n";
    	$expseries = $self->util_kbase_store()->get_object($params->{expseries_workspace}."/".$params->{expseries_id});
    }
    if (!defined($params->{media_id})) {
    	$params->{media_id} = "Complete";
    	$params->{media_workspace} = "KBaseMedia";
    }
    print "Retrieving ".$params->{media_id}." media.\n";
    my $media = $self->util_kbase_store()->get_object($params->{media_workspace}."/".$params->{media_id});
    print "Preparing flux balance analysis problem.\n";
    
    
    print "Running flux balance analysis problem.\n";
    
    
    print "Saving FBA object with gapfilling sensitivity analysis and flux.\n";
    #$wsmeta = $self->util_kbase_store()->save_object($pheno,$params->{workspace}."/".$params->{phenotypesim_output_id}.".".$gfid);
	#$output->{new_phenotypesim_ref} = $params->{workspace}."/".$params->{phenotypesim_output_id}.".".$gfid;
	#return $output;
}

sub func_merge_metabolic_models_into_community_model {
	my ($self,$params) = @_;
    $params = $self->util_validate_args($params,["workspace","fbamodel_id_list","fbamodel_output_id"],{
    	fbamodel_workspace => $params->{workspace},
    	mixed_bag_model => 0
    });
    #Getting genome
	print "Retrieving first model.\n";
	my $model = $self->util_kbase_store()->get_object($params->{fbamodel_workspace}."/".$params->{fbamodel_id_list}->[0]);
	#Creating new community model
	my $commdl = Bio::KBase::ObjectAPI::KBaseFBA::FBAModel->new({
		source_id => $params->{fbamodel_output_id},
		source => "KBase",
		id => $params->{fbamodel_output_id},
		type => "CommunityModel",
		name => $params->{fbamodel_output_id},
		template_ref => $model->template_ref(),
		template_refs => [$model->template_ref()],
		genome_ref => $params->{workspace}."/".$params->{fbamodel_output_id}.".genome",
		modelreactions => [],
		modelcompounds => [],
		modelcompartments => [],
		biomasses => [],
		gapgens => [],
		gapfillings => [],
	});
	$commdl->parent($self->util_kbase_store());
	for (my $i=0; $i < @{$params->{fbamodel_id_list}}; $i++) {
		$params->{fbamodel_id_list}->[$i] = $params->{fbamodel_workspace}."/".$params->{fbamodel_id_list}->[$i];
	}
	print "Merging models.\n";
	my $genomeObj = $commdl->merge_models({
		models => $params->{fbamodel_id_list},
		mixed_bag_model => $params->{mixed_bag_model}
	});
	print "Saving model and combined genome.\n";
	my $wsmeta = $self->util_kbase_store()->save_object($genomeObj,$params->{workspace}."/".$params->{fbamodel_output_id}.".genome");
	$wsmeta = $self->util_kbase_store()->save_object($commdl,$params->{workspace}."/".$params->{fbamodel_output_id});
	return {
		new_fbamodel_ref => $params->{workspace}."/".$params->{fbamodel_output_id}
	};
}

#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR
    
    my $config_file = $ENV{ KB_DEPLOYMENT_CONFIG };
    my $cfg = Config::IniFiles->new(-file=>$config_file);
    my $wsInstance = $cfg->val('fba_tools','workspace-url');
    die "no workspace-url defined" unless $wsInstance;
    
    $self->{'workspace-url'} = $wsInstance;
    my $confighash = {};
    my $params = [$cfg->Parameters('fba_tools')];
    my $paramhash = {};
    foreach my $param (@{$params}) {
    	$paramhash->{$param} = $cfg->val('fba_tools',$param);
    }
    Bio::KBase::ObjectAPI::config::all_params($paramhash);
    
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 build_metabolic_model

  $return = $obj->build_metabolic_model($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a fba_tools.BuildMetabolicModelParams
$return is a fba_tools.BuildMetabolicModelResults
BuildMetabolicModelParams is a reference to a hash where the following keys are defined:
	genome_id has a value which is a fba_tools.genome_id
	genome_workspace has a value which is a fba_tools.workspace_name
	media_id has a value which is a fba_tools.media_id
	media_workspace has a value which is a fba_tools.workspace_name
	fbamodel_output_id has a value which is a fba_tools.fbamodel_id
	workspace has a value which is a fba_tools.workspace_name
	template_id has a value which is a fba_tools.template_id
	template_workspace has a value which is a fba_tools.workspace_name
	coremodel has a value which is a fba_tools.bool
	gapfill_model has a value which is a fba_tools.bool
	thermodynamic_constraints has a value which is a fba_tools.bool
	comprehensive_gapfill has a value which is a fba_tools.bool
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
	expseries_id has a value which is a fba_tools.expseries_id
	expseries_workspace has a value which is a fba_tools.workspace_name
	exp_condition has a value which is a string
	exp_threshold_percentile has a value which is a float
	exp_threshold_margin has a value which is a float
	activation_coefficient has a value which is a float
	omega has a value which is a float
	objective_fraction has a value which is a float
	minimum_target_flux has a value which is a float
	number_of_solutions has a value which is an int
genome_id is a string
workspace_name is a string
media_id is a string
fbamodel_id is a string
template_id is a string
bool is an int
compound_id is a string
expseries_id is a string
BuildMetabolicModelResults is a reference to a hash where the following keys are defined:
	new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
	new_fba_ref has a value which is a fba_tools.ws_fba_id
	number_gapfilled_reactions has a value which is an int
	number_removed_biomass_compounds has a value which is an int
ws_fbamodel_id is a string
ws_fba_id is a string

</pre>

=end html

=begin text

$params is a fba_tools.BuildMetabolicModelParams
$return is a fba_tools.BuildMetabolicModelResults
BuildMetabolicModelParams is a reference to a hash where the following keys are defined:
	genome_id has a value which is a fba_tools.genome_id
	genome_workspace has a value which is a fba_tools.workspace_name
	media_id has a value which is a fba_tools.media_id
	media_workspace has a value which is a fba_tools.workspace_name
	fbamodel_output_id has a value which is a fba_tools.fbamodel_id
	workspace has a value which is a fba_tools.workspace_name
	template_id has a value which is a fba_tools.template_id
	template_workspace has a value which is a fba_tools.workspace_name
	coremodel has a value which is a fba_tools.bool
	gapfill_model has a value which is a fba_tools.bool
	thermodynamic_constraints has a value which is a fba_tools.bool
	comprehensive_gapfill has a value which is a fba_tools.bool
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
	expseries_id has a value which is a fba_tools.expseries_id
	expseries_workspace has a value which is a fba_tools.workspace_name
	exp_condition has a value which is a string
	exp_threshold_percentile has a value which is a float
	exp_threshold_margin has a value which is a float
	activation_coefficient has a value which is a float
	omega has a value which is a float
	objective_fraction has a value which is a float
	minimum_target_flux has a value which is a float
	number_of_solutions has a value which is an int
genome_id is a string
workspace_name is a string
media_id is a string
fbamodel_id is a string
template_id is a string
bool is an int
compound_id is a string
expseries_id is a string
BuildMetabolicModelResults is a reference to a hash where the following keys are defined:
	new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
	new_fba_ref has a value which is a fba_tools.ws_fba_id
	number_gapfilled_reactions has a value which is an int
	number_removed_biomass_compounds has a value which is an int
ws_fbamodel_id is a string
ws_fba_id is a string


=end text



=item Description

Build a genome-scale metabolic model based on annotations in an input genome typed object

=back

=cut

sub build_metabolic_model
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to build_metabolic_model:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'build_metabolic_model');
    }

    my $ctx = $fba_tools::fba_toolsServer::CallContext;
    my($return);
    #BEGIN build_metabolic_model
    $self->util_initialize_call($params,$ctx);
	$return = $self->func_build_metabolic_model($params);
    #END build_metabolic_model
    my @_bad_returns;
    (ref($return) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"return\" (value was \"$return\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to build_metabolic_model:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'build_metabolic_model');
    }
    return($return);
}




=head2 gapfill_metabolic_model

  $results = $obj->gapfill_metabolic_model($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a fba_tools.GapfillMetabolicModelParams
$results is a fba_tools.GapfillMetabolicModelResults
GapfillMetabolicModelParams is a reference to a hash where the following keys are defined:
	fbamodel_id has a value which is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	media_id has a value which is a fba_tools.media_id
	media_workspace has a value which is a fba_tools.workspace_name
	target_reaction has a value which is a fba_tools.reaction_id
	fbamodel_output_id has a value which is a fba_tools.fbamodel_id
	workspace has a value which is a fba_tools.workspace_name
	thermodynamic_constraints has a value which is a fba_tools.bool
	comprehensive_gapfill has a value which is a fba_tools.bool
	source_fbamodel_id has a value which is a fba_tools.fbamodel_id
	source_fbamodel_workspace has a value which is a fba_tools.workspace_name
	feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
	reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
	expseries_id has a value which is a fba_tools.expseries_id
	expseries_workspace has a value which is a fba_tools.workspace_name
	exp_condition has a value which is a string
	exp_threshold_percentile has a value which is a float
	exp_threshold_margin has a value which is a float
	activation_coefficient has a value which is a float
	omega has a value which is a float
	objective_fraction has a value which is a float
	minimum_target_flux has a value which is a float
	number_of_solutions has a value which is an int
fbamodel_id is a string
workspace_name is a string
media_id is a string
reaction_id is a string
bool is an int
feature_id is a string
compound_id is a string
expseries_id is a string
GapfillMetabolicModelResults is a reference to a hash where the following keys are defined:
	new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
	new_fba_ref has a value which is a fba_tools.ws_fba_id
	number_gapfilled_reactions has a value which is an int
	number_removed_biomass_compounds has a value which is an int
ws_fbamodel_id is a string
ws_fba_id is a string

</pre>

=end html

=begin text

$params is a fba_tools.GapfillMetabolicModelParams
$results is a fba_tools.GapfillMetabolicModelResults
GapfillMetabolicModelParams is a reference to a hash where the following keys are defined:
	fbamodel_id has a value which is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	media_id has a value which is a fba_tools.media_id
	media_workspace has a value which is a fba_tools.workspace_name
	target_reaction has a value which is a fba_tools.reaction_id
	fbamodel_output_id has a value which is a fba_tools.fbamodel_id
	workspace has a value which is a fba_tools.workspace_name
	thermodynamic_constraints has a value which is a fba_tools.bool
	comprehensive_gapfill has a value which is a fba_tools.bool
	source_fbamodel_id has a value which is a fba_tools.fbamodel_id
	source_fbamodel_workspace has a value which is a fba_tools.workspace_name
	feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
	reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
	expseries_id has a value which is a fba_tools.expseries_id
	expseries_workspace has a value which is a fba_tools.workspace_name
	exp_condition has a value which is a string
	exp_threshold_percentile has a value which is a float
	exp_threshold_margin has a value which is a float
	activation_coefficient has a value which is a float
	omega has a value which is a float
	objective_fraction has a value which is a float
	minimum_target_flux has a value which is a float
	number_of_solutions has a value which is an int
fbamodel_id is a string
workspace_name is a string
media_id is a string
reaction_id is a string
bool is an int
feature_id is a string
compound_id is a string
expseries_id is a string
GapfillMetabolicModelResults is a reference to a hash where the following keys are defined:
	new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
	new_fba_ref has a value which is a fba_tools.ws_fba_id
	number_gapfilled_reactions has a value which is an int
	number_removed_biomass_compounds has a value which is an int
ws_fbamodel_id is a string
ws_fba_id is a string


=end text



=item Description

Gapfills a metabolic model to induce flux in a specified reaction

=back

=cut

sub gapfill_metabolic_model
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to gapfill_metabolic_model:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'gapfill_metabolic_model');
    }

    my $ctx = $fba_tools::fba_toolsServer::CallContext;
    my($results);
    #BEGIN gapfill_metabolic_model
    $self->util_initialize_call($params,$ctx);
	$results = $self->func_gapfill_metabolic_model($params);
    #END gapfill_metabolic_model
    my @_bad_returns;
    (ref($results) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"results\" (value was \"$results\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to gapfill_metabolic_model:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'gapfill_metabolic_model');
    }
    return($results);
}




=head2 run_flux_balance_analysis

  $results = $obj->run_flux_balance_analysis($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a fba_tools.RunFluxBalanceAnalysisParams
$results is a fba_tools.RunFluxBalanceAnalysisResults
RunFluxBalanceAnalysisParams is a reference to a hash where the following keys are defined:
	fbamodel_id has a value which is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	media_id has a value which is a fba_tools.media_id
	media_workspace has a value which is a fba_tools.workspace_name
	target_reaction has a value which is a fba_tools.reaction_id
	fba_output_id has a value which is a fba_tools.fba_id
	workspace has a value which is a fba_tools.workspace_name
	thermodynamic_constraints has a value which is a fba_tools.bool
	fva has a value which is a fba_tools.bool
	minimize_flux has a value which is a fba_tools.bool
	simulate_ko has a value which is a fba_tools.bool
	find_min_media has a value which is a fba_tools.bool
	all_reversible has a value which is a fba_tools.bool
	feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
	reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
	expseries_id has a value which is a fba_tools.expseries_id
	expseries_workspace has a value which is a fba_tools.workspace_name
	exp_condition has a value which is a string
	exp_threshold_percentile has a value which is a float
	exp_threshold_margin has a value which is a float
	activation_coefficient has a value which is a float
	omega has a value which is a float
	objective_fraction has a value which is a float
	max_c_uptake has a value which is a float
	max_n_uptake has a value which is a float
	max_p_uptake has a value which is a float
	max_s_uptake has a value which is a float
	max_o_uptake has a value which is a float
	default_max_uptake has a value which is a float
	notes has a value which is a string
	massbalance has a value which is a string
fbamodel_id is a string
workspace_name is a string
media_id is a string
reaction_id is a string
fba_id is a string
bool is an int
feature_id is a string
compound_id is a string
expseries_id is a string
RunFluxBalanceAnalysisResults is a reference to a hash where the following keys are defined:
	new_fba_ref has a value which is a fba_tools.ws_fba_id
	objective has a value which is an int
ws_fba_id is a string

</pre>

=end html

=begin text

$params is a fba_tools.RunFluxBalanceAnalysisParams
$results is a fba_tools.RunFluxBalanceAnalysisResults
RunFluxBalanceAnalysisParams is a reference to a hash where the following keys are defined:
	fbamodel_id has a value which is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	media_id has a value which is a fba_tools.media_id
	media_workspace has a value which is a fba_tools.workspace_name
	target_reaction has a value which is a fba_tools.reaction_id
	fba_output_id has a value which is a fba_tools.fba_id
	workspace has a value which is a fba_tools.workspace_name
	thermodynamic_constraints has a value which is a fba_tools.bool
	fva has a value which is a fba_tools.bool
	minimize_flux has a value which is a fba_tools.bool
	simulate_ko has a value which is a fba_tools.bool
	find_min_media has a value which is a fba_tools.bool
	all_reversible has a value which is a fba_tools.bool
	feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
	reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
	expseries_id has a value which is a fba_tools.expseries_id
	expseries_workspace has a value which is a fba_tools.workspace_name
	exp_condition has a value which is a string
	exp_threshold_percentile has a value which is a float
	exp_threshold_margin has a value which is a float
	activation_coefficient has a value which is a float
	omega has a value which is a float
	objective_fraction has a value which is a float
	max_c_uptake has a value which is a float
	max_n_uptake has a value which is a float
	max_p_uptake has a value which is a float
	max_s_uptake has a value which is a float
	max_o_uptake has a value which is a float
	default_max_uptake has a value which is a float
	notes has a value which is a string
	massbalance has a value which is a string
fbamodel_id is a string
workspace_name is a string
media_id is a string
reaction_id is a string
fba_id is a string
bool is an int
feature_id is a string
compound_id is a string
expseries_id is a string
RunFluxBalanceAnalysisResults is a reference to a hash where the following keys are defined:
	new_fba_ref has a value which is a fba_tools.ws_fba_id
	objective has a value which is an int
ws_fba_id is a string


=end text



=item Description

Run flux balance analysis and return ID of FBA object with results

=back

=cut

sub run_flux_balance_analysis
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to run_flux_balance_analysis:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'run_flux_balance_analysis');
    }

    my $ctx = $fba_tools::fba_toolsServer::CallContext;
    my($results);
    #BEGIN run_flux_balance_analysis
    $self->util_initialize_call($params,$ctx);
	$results = $self->func_run_flux_balance_analysis($params);
    #END run_flux_balance_analysis
    my @_bad_returns;
    (ref($results) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"results\" (value was \"$results\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to run_flux_balance_analysis:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'run_flux_balance_analysis');
    }
    return($results);
}




=head2 compare_fba_solutions

  $results = $obj->compare_fba_solutions($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a fba_tools.CompareFBASolutionsParams
$results is a fba_tools.CompareFBASolutionsResults
CompareFBASolutionsParams is a reference to a hash where the following keys are defined:
	fba_id_list has a value which is a reference to a list where each element is a fba_tools.fba_id
	fba_workspace has a value which is a fba_tools.workspace_name
	fbacomparison_output_id has a value which is a fba_tools.fbacomparison_id
	workspace has a value which is a fba_tools.workspace_name
fba_id is a string
workspace_name is a string
fbacomparison_id is a string
CompareFBASolutionsResults is a reference to a hash where the following keys are defined:
	new_fbacomparison_ref has a value which is a fba_tools.ws_fbacomparison_id
ws_fbacomparison_id is a string

</pre>

=end html

=begin text

$params is a fba_tools.CompareFBASolutionsParams
$results is a fba_tools.CompareFBASolutionsResults
CompareFBASolutionsParams is a reference to a hash where the following keys are defined:
	fba_id_list has a value which is a reference to a list where each element is a fba_tools.fba_id
	fba_workspace has a value which is a fba_tools.workspace_name
	fbacomparison_output_id has a value which is a fba_tools.fbacomparison_id
	workspace has a value which is a fba_tools.workspace_name
fba_id is a string
workspace_name is a string
fbacomparison_id is a string
CompareFBASolutionsResults is a reference to a hash where the following keys are defined:
	new_fbacomparison_ref has a value which is a fba_tools.ws_fbacomparison_id
ws_fbacomparison_id is a string


=end text



=item Description

Compares multiple FBA solutions and saves comparison as a new object in the workspace

=back

=cut

sub compare_fba_solutions
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to compare_fba_solutions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'compare_fba_solutions');
    }

    my $ctx = $fba_tools::fba_toolsServer::CallContext;
    my($results);
    #BEGIN compare_fba_solutions
    $self->util_initialize_call($params,$ctx);
	$results = $self->func_compare_fba_solutions($params);
    #END compare_fba_solutions
    my @_bad_returns;
    (ref($results) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"results\" (value was \"$results\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to compare_fba_solutions:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'compare_fba_solutions');
    }
    return($results);
}




=head2 propagate_model_to_new_genome

  $results = $obj->propagate_model_to_new_genome($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a fba_tools.PropagateModelToNewGenomeParams
$results is a fba_tools.PropagateModelToNewGenomeResults
PropagateModelToNewGenomeParams is a reference to a hash where the following keys are defined:
	fbamodel_id has a value which is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	proteincomparison_id has a value which is a fba_tools.proteincomparison_id
	proteincomparison_workspace has a value which is a fba_tools.workspace_name
	fbamodel_output_id has a value which is a fba_tools.fbamodel_id
	workspace has a value which is a fba_tools.workspace_name
	keep_nogene_rxn has a value which is a fba_tools.bool
	gapfill_model has a value which is a fba_tools.bool
	media_id has a value which is a fba_tools.media_id
	media_workspace has a value which is a fba_tools.workspace_name
	thermodynamic_constraints has a value which is a fba_tools.bool
	comprehensive_gapfill has a value which is a fba_tools.bool
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
	expseries_id has a value which is a fba_tools.expseries_id
	expseries_workspace has a value which is a fba_tools.workspace_name
	exp_condition has a value which is a string
	exp_threshold_percentile has a value which is a float
	exp_threshold_margin has a value which is a float
	activation_coefficient has a value which is a float
	omega has a value which is a float
	objective_fraction has a value which is a float
	minimum_target_flux has a value which is a float
	number_of_solutions has a value which is an int
fbamodel_id is a string
workspace_name is a string
proteincomparison_id is a string
bool is an int
media_id is a string
compound_id is a string
expseries_id is a string
PropagateModelToNewGenomeResults is a reference to a hash where the following keys are defined:
	new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
	new_fba_ref has a value which is a fba_tools.ws_fba_id
	number_gapfilled_reactions has a value which is an int
	number_removed_biomass_compounds has a value which is an int
ws_fbamodel_id is a string
ws_fba_id is a string

</pre>

=end html

=begin text

$params is a fba_tools.PropagateModelToNewGenomeParams
$results is a fba_tools.PropagateModelToNewGenomeResults
PropagateModelToNewGenomeParams is a reference to a hash where the following keys are defined:
	fbamodel_id has a value which is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	proteincomparison_id has a value which is a fba_tools.proteincomparison_id
	proteincomparison_workspace has a value which is a fba_tools.workspace_name
	fbamodel_output_id has a value which is a fba_tools.fbamodel_id
	workspace has a value which is a fba_tools.workspace_name
	keep_nogene_rxn has a value which is a fba_tools.bool
	gapfill_model has a value which is a fba_tools.bool
	media_id has a value which is a fba_tools.media_id
	media_workspace has a value which is a fba_tools.workspace_name
	thermodynamic_constraints has a value which is a fba_tools.bool
	comprehensive_gapfill has a value which is a fba_tools.bool
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
	expseries_id has a value which is a fba_tools.expseries_id
	expseries_workspace has a value which is a fba_tools.workspace_name
	exp_condition has a value which is a string
	exp_threshold_percentile has a value which is a float
	exp_threshold_margin has a value which is a float
	activation_coefficient has a value which is a float
	omega has a value which is a float
	objective_fraction has a value which is a float
	minimum_target_flux has a value which is a float
	number_of_solutions has a value which is an int
fbamodel_id is a string
workspace_name is a string
proteincomparison_id is a string
bool is an int
media_id is a string
compound_id is a string
expseries_id is a string
PropagateModelToNewGenomeResults is a reference to a hash where the following keys are defined:
	new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
	new_fba_ref has a value which is a fba_tools.ws_fba_id
	number_gapfilled_reactions has a value which is an int
	number_removed_biomass_compounds has a value which is an int
ws_fbamodel_id is a string
ws_fba_id is a string


=end text



=item Description

Translate the metabolic model of one organism to another, using a mapping of similar proteins between their genomes

=back

=cut

sub propagate_model_to_new_genome
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to propagate_model_to_new_genome:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'propagate_model_to_new_genome');
    }

    my $ctx = $fba_tools::fba_toolsServer::CallContext;
    my($results);
    #BEGIN propagate_model_to_new_genome
    $self->util_initialize_call($params,$ctx);
	$results = $self->func_propagate_model_to_new_genome($params);
    #END propagate_model_to_new_genome
    my @_bad_returns;
    (ref($results) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"results\" (value was \"$results\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to propagate_model_to_new_genome:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'propagate_model_to_new_genome');
    }
    return($results);
}




=head2 simulate_growth_on_phenotype_data

  $results = $obj->simulate_growth_on_phenotype_data($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a fba_tools.SimulateGrowthOnPhenotypeDataParams
$results is a fba_tools.SimulateGrowthOnPhenotypeDataResults
SimulateGrowthOnPhenotypeDataParams is a reference to a hash where the following keys are defined:
	fbamodel_id has a value which is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	phenotypeset_id has a value which is a fba_tools.phenotypeset_id
	phenotypeset_workspace has a value which is a fba_tools.workspace_name
	phenotypesim_output_id has a value which is a fba_tools.phenotypesim_id
	workspace has a value which is a fba_tools.workspace_name
	all_reversible has a value which is a fba_tools.bool
	feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
	reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
fbamodel_id is a string
workspace_name is a string
phenotypeset_id is a string
phenotypesim_id is a string
bool is an int
feature_id is a string
reaction_id is a string
compound_id is a string
SimulateGrowthOnPhenotypeDataResults is a reference to a hash where the following keys are defined:
	new_phenotypesim_ref has a value which is a fba_tools.ws_phenotypesim_id
ws_phenotypesim_id is a string

</pre>

=end html

=begin text

$params is a fba_tools.SimulateGrowthOnPhenotypeDataParams
$results is a fba_tools.SimulateGrowthOnPhenotypeDataResults
SimulateGrowthOnPhenotypeDataParams is a reference to a hash where the following keys are defined:
	fbamodel_id has a value which is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	phenotypeset_id has a value which is a fba_tools.phenotypeset_id
	phenotypeset_workspace has a value which is a fba_tools.workspace_name
	phenotypesim_output_id has a value which is a fba_tools.phenotypesim_id
	workspace has a value which is a fba_tools.workspace_name
	all_reversible has a value which is a fba_tools.bool
	feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
	reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
	custom_bound_list has a value which is a reference to a list where each element is a string
	media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
fbamodel_id is a string
workspace_name is a string
phenotypeset_id is a string
phenotypesim_id is a string
bool is an int
feature_id is a string
reaction_id is a string
compound_id is a string
SimulateGrowthOnPhenotypeDataResults is a reference to a hash where the following keys are defined:
	new_phenotypesim_ref has a value which is a fba_tools.ws_phenotypesim_id
ws_phenotypesim_id is a string


=end text



=item Description

Use Flux Balance Analysis (FBA) to simulate multiple growth phenotypes.

=back

=cut

sub simulate_growth_on_phenotype_data
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to simulate_growth_on_phenotype_data:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'simulate_growth_on_phenotype_data');
    }

    my $ctx = $fba_tools::fba_toolsServer::CallContext;
    my($results);
    #BEGIN simulate_growth_on_phenotype_data
    $self->util_initialize_call($params,$ctx);
	$results = $self->func_simulate_growth_on_phenotype_data($params);
    #END simulate_growth_on_phenotype_data
    my @_bad_returns;
    (ref($results) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"results\" (value was \"$results\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to simulate_growth_on_phenotype_data:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'simulate_growth_on_phenotype_data');
    }
    return($results);
}




=head2 merge_metabolic_models_into_community_model

  $results = $obj->merge_metabolic_models_into_community_model($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a fba_tools.MergeMetabolicModelsIntoCommunityModelParams
$results is a fba_tools.MergeMetabolicModelsIntoCommunityModelResults
MergeMetabolicModelsIntoCommunityModelParams is a reference to a hash where the following keys are defined:
	fbamodel_id_list has a value which is a reference to a list where each element is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	fbamodel_output_id has a value which is a fba_tools.fbamodel_id
	workspace has a value which is a fba_tools.workspace_name
	mixed_bag_model has a value which is a fba_tools.bool
fbamodel_id is a string
workspace_name is a string
bool is an int
MergeMetabolicModelsIntoCommunityModelResults is a reference to a hash where the following keys are defined:
	new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
ws_fbamodel_id is a string

</pre>

=end html

=begin text

$params is a fba_tools.MergeMetabolicModelsIntoCommunityModelParams
$results is a fba_tools.MergeMetabolicModelsIntoCommunityModelResults
MergeMetabolicModelsIntoCommunityModelParams is a reference to a hash where the following keys are defined:
	fbamodel_id_list has a value which is a reference to a list where each element is a fba_tools.fbamodel_id
	fbamodel_workspace has a value which is a fba_tools.workspace_name
	fbamodel_output_id has a value which is a fba_tools.fbamodel_id
	workspace has a value which is a fba_tools.workspace_name
	mixed_bag_model has a value which is a fba_tools.bool
fbamodel_id is a string
workspace_name is a string
bool is an int
MergeMetabolicModelsIntoCommunityModelResults is a reference to a hash where the following keys are defined:
	new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
ws_fbamodel_id is a string


=end text



=item Description

Merge two or more metabolic models into a compartmentalized community model

=back

=cut

sub merge_metabolic_models_into_community_model
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to merge_metabolic_models_into_community_model:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'merge_metabolic_models_into_community_model');
    }

    my $ctx = $fba_tools::fba_toolsServer::CallContext;
    my($results);
    #BEGIN merge_metabolic_models_into_community_model
    $self->util_initialize_call($params,$ctx);
	$results = $self->func_merge_metabolic_models_into_community_model($params);
    #END merge_metabolic_models_into_community_model
    my @_bad_returns;
    (ref($results) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"results\" (value was \"$results\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to merge_metabolic_models_into_community_model:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'merge_metabolic_models_into_community_model');
    }
    return($results);
}




=head2 version 

  $return = $obj->version()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a string
</pre>

=end html

=begin text

$return is a string

=end text

=item Description

Return the module version. This is a Semantic Versioning number.

=back

=cut

sub version {
    return $VERSION;
}

=head1 TYPES



=head2 bool

=over 4



=item Description

A binary boolean


=item Definition

=begin html

<pre>
an int
</pre>

=end html

=begin text

an int

=end text

=back



=head2 genome_id

=over 4



=item Description

A string representing a Genome id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 media_id

=over 4



=item Description

A string representing a Media id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 template_id

=over 4



=item Description

A string representing a NewModelTemplate id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 fbamodel_id

=over 4



=item Description

A string representing a FBAModel id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 proteincomparison_id

=over 4



=item Description

A string representing a protein comparison id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 fba_id

=over 4



=item Description

A string representing a FBA id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 fbacomparison_id

=over 4



=item Description

A string representing a FBA comparison id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 phenotypeset_id

=over 4



=item Description

A string representing a phenotype set id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 phenotypesim_id

=over 4



=item Description

A string representing a phenotype simulation id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 expseries_id

=over 4



=item Description

A string representing an expression matrix id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 reaction_id

=over 4



=item Description

A string representing a reaction id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 feature_id

=over 4



=item Description

A string representing a feature id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 compound_id

=over 4



=item Description

A string representing a compound id.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 workspace_name

=over 4



=item Description

A string representing a workspace name.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ws_fbamodel_id

=over 4



=item Description

The workspace ID for a FBAModel data object.
@id ws KBaseFBA.FBAModel


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ws_fba_id

=over 4



=item Description

The workspace ID for a FBA data object.
@id ws KBaseFBA.FBA


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ws_fbacomparison_id

=over 4



=item Description

The workspace ID for a FBA data object.
@id ws KBaseFBA.FBA


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ws_phenotypesim_id

=over 4



=item Description

The workspace ID for a phenotype set simulation object.
@id ws KBasePhenotypes.PhenotypeSimulationSet


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 BuildMetabolicModelParams

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
genome_id has a value which is a fba_tools.genome_id
genome_workspace has a value which is a fba_tools.workspace_name
media_id has a value which is a fba_tools.media_id
media_workspace has a value which is a fba_tools.workspace_name
fbamodel_output_id has a value which is a fba_tools.fbamodel_id
workspace has a value which is a fba_tools.workspace_name
template_id has a value which is a fba_tools.template_id
template_workspace has a value which is a fba_tools.workspace_name
coremodel has a value which is a fba_tools.bool
gapfill_model has a value which is a fba_tools.bool
thermodynamic_constraints has a value which is a fba_tools.bool
comprehensive_gapfill has a value which is a fba_tools.bool
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
expseries_id has a value which is a fba_tools.expseries_id
expseries_workspace has a value which is a fba_tools.workspace_name
exp_condition has a value which is a string
exp_threshold_percentile has a value which is a float
exp_threshold_margin has a value which is a float
activation_coefficient has a value which is a float
omega has a value which is a float
objective_fraction has a value which is a float
minimum_target_flux has a value which is a float
number_of_solutions has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
genome_id has a value which is a fba_tools.genome_id
genome_workspace has a value which is a fba_tools.workspace_name
media_id has a value which is a fba_tools.media_id
media_workspace has a value which is a fba_tools.workspace_name
fbamodel_output_id has a value which is a fba_tools.fbamodel_id
workspace has a value which is a fba_tools.workspace_name
template_id has a value which is a fba_tools.template_id
template_workspace has a value which is a fba_tools.workspace_name
coremodel has a value which is a fba_tools.bool
gapfill_model has a value which is a fba_tools.bool
thermodynamic_constraints has a value which is a fba_tools.bool
comprehensive_gapfill has a value which is a fba_tools.bool
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
expseries_id has a value which is a fba_tools.expseries_id
expseries_workspace has a value which is a fba_tools.workspace_name
exp_condition has a value which is a string
exp_threshold_percentile has a value which is a float
exp_threshold_margin has a value which is a float
activation_coefficient has a value which is a float
omega has a value which is a float
objective_fraction has a value which is a float
minimum_target_flux has a value which is a float
number_of_solutions has a value which is an int


=end text

=back



=head2 BuildMetabolicModelResults

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
new_fba_ref has a value which is a fba_tools.ws_fba_id
number_gapfilled_reactions has a value which is an int
number_removed_biomass_compounds has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
new_fba_ref has a value which is a fba_tools.ws_fba_id
number_gapfilled_reactions has a value which is an int
number_removed_biomass_compounds has a value which is an int


=end text

=back



=head2 GapfillMetabolicModelParams

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
fbamodel_id has a value which is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
media_id has a value which is a fba_tools.media_id
media_workspace has a value which is a fba_tools.workspace_name
target_reaction has a value which is a fba_tools.reaction_id
fbamodel_output_id has a value which is a fba_tools.fbamodel_id
workspace has a value which is a fba_tools.workspace_name
thermodynamic_constraints has a value which is a fba_tools.bool
comprehensive_gapfill has a value which is a fba_tools.bool
source_fbamodel_id has a value which is a fba_tools.fbamodel_id
source_fbamodel_workspace has a value which is a fba_tools.workspace_name
feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
expseries_id has a value which is a fba_tools.expseries_id
expseries_workspace has a value which is a fba_tools.workspace_name
exp_condition has a value which is a string
exp_threshold_percentile has a value which is a float
exp_threshold_margin has a value which is a float
activation_coefficient has a value which is a float
omega has a value which is a float
objective_fraction has a value which is a float
minimum_target_flux has a value which is a float
number_of_solutions has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
fbamodel_id has a value which is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
media_id has a value which is a fba_tools.media_id
media_workspace has a value which is a fba_tools.workspace_name
target_reaction has a value which is a fba_tools.reaction_id
fbamodel_output_id has a value which is a fba_tools.fbamodel_id
workspace has a value which is a fba_tools.workspace_name
thermodynamic_constraints has a value which is a fba_tools.bool
comprehensive_gapfill has a value which is a fba_tools.bool
source_fbamodel_id has a value which is a fba_tools.fbamodel_id
source_fbamodel_workspace has a value which is a fba_tools.workspace_name
feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
expseries_id has a value which is a fba_tools.expseries_id
expseries_workspace has a value which is a fba_tools.workspace_name
exp_condition has a value which is a string
exp_threshold_percentile has a value which is a float
exp_threshold_margin has a value which is a float
activation_coefficient has a value which is a float
omega has a value which is a float
objective_fraction has a value which is a float
minimum_target_flux has a value which is a float
number_of_solutions has a value which is an int


=end text

=back



=head2 GapfillMetabolicModelResults

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
new_fba_ref has a value which is a fba_tools.ws_fba_id
number_gapfilled_reactions has a value which is an int
number_removed_biomass_compounds has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
new_fba_ref has a value which is a fba_tools.ws_fba_id
number_gapfilled_reactions has a value which is an int
number_removed_biomass_compounds has a value which is an int


=end text

=back



=head2 RunFluxBalanceAnalysisParams

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
fbamodel_id has a value which is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
media_id has a value which is a fba_tools.media_id
media_workspace has a value which is a fba_tools.workspace_name
target_reaction has a value which is a fba_tools.reaction_id
fba_output_id has a value which is a fba_tools.fba_id
workspace has a value which is a fba_tools.workspace_name
thermodynamic_constraints has a value which is a fba_tools.bool
fva has a value which is a fba_tools.bool
minimize_flux has a value which is a fba_tools.bool
simulate_ko has a value which is a fba_tools.bool
find_min_media has a value which is a fba_tools.bool
all_reversible has a value which is a fba_tools.bool
feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
expseries_id has a value which is a fba_tools.expseries_id
expseries_workspace has a value which is a fba_tools.workspace_name
exp_condition has a value which is a string
exp_threshold_percentile has a value which is a float
exp_threshold_margin has a value which is a float
activation_coefficient has a value which is a float
omega has a value which is a float
objective_fraction has a value which is a float
max_c_uptake has a value which is a float
max_n_uptake has a value which is a float
max_p_uptake has a value which is a float
max_s_uptake has a value which is a float
max_o_uptake has a value which is a float
default_max_uptake has a value which is a float
notes has a value which is a string
massbalance has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
fbamodel_id has a value which is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
media_id has a value which is a fba_tools.media_id
media_workspace has a value which is a fba_tools.workspace_name
target_reaction has a value which is a fba_tools.reaction_id
fba_output_id has a value which is a fba_tools.fba_id
workspace has a value which is a fba_tools.workspace_name
thermodynamic_constraints has a value which is a fba_tools.bool
fva has a value which is a fba_tools.bool
minimize_flux has a value which is a fba_tools.bool
simulate_ko has a value which is a fba_tools.bool
find_min_media has a value which is a fba_tools.bool
all_reversible has a value which is a fba_tools.bool
feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
expseries_id has a value which is a fba_tools.expseries_id
expseries_workspace has a value which is a fba_tools.workspace_name
exp_condition has a value which is a string
exp_threshold_percentile has a value which is a float
exp_threshold_margin has a value which is a float
activation_coefficient has a value which is a float
omega has a value which is a float
objective_fraction has a value which is a float
max_c_uptake has a value which is a float
max_n_uptake has a value which is a float
max_p_uptake has a value which is a float
max_s_uptake has a value which is a float
max_o_uptake has a value which is a float
default_max_uptake has a value which is a float
notes has a value which is a string
massbalance has a value which is a string


=end text

=back



=head2 RunFluxBalanceAnalysisResults

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_fba_ref has a value which is a fba_tools.ws_fba_id
objective has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_fba_ref has a value which is a fba_tools.ws_fba_id
objective has a value which is an int


=end text

=back



=head2 CompareFBASolutionsParams

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
fba_id_list has a value which is a reference to a list where each element is a fba_tools.fba_id
fba_workspace has a value which is a fba_tools.workspace_name
fbacomparison_output_id has a value which is a fba_tools.fbacomparison_id
workspace has a value which is a fba_tools.workspace_name

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
fba_id_list has a value which is a reference to a list where each element is a fba_tools.fba_id
fba_workspace has a value which is a fba_tools.workspace_name
fbacomparison_output_id has a value which is a fba_tools.fbacomparison_id
workspace has a value which is a fba_tools.workspace_name


=end text

=back



=head2 CompareFBASolutionsResults

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_fbacomparison_ref has a value which is a fba_tools.ws_fbacomparison_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_fbacomparison_ref has a value which is a fba_tools.ws_fbacomparison_id


=end text

=back



=head2 PropagateModelToNewGenomeParams

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
fbamodel_id has a value which is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
proteincomparison_id has a value which is a fba_tools.proteincomparison_id
proteincomparison_workspace has a value which is a fba_tools.workspace_name
fbamodel_output_id has a value which is a fba_tools.fbamodel_id
workspace has a value which is a fba_tools.workspace_name
keep_nogene_rxn has a value which is a fba_tools.bool
gapfill_model has a value which is a fba_tools.bool
media_id has a value which is a fba_tools.media_id
media_workspace has a value which is a fba_tools.workspace_name
thermodynamic_constraints has a value which is a fba_tools.bool
comprehensive_gapfill has a value which is a fba_tools.bool
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
expseries_id has a value which is a fba_tools.expseries_id
expseries_workspace has a value which is a fba_tools.workspace_name
exp_condition has a value which is a string
exp_threshold_percentile has a value which is a float
exp_threshold_margin has a value which is a float
activation_coefficient has a value which is a float
omega has a value which is a float
objective_fraction has a value which is a float
minimum_target_flux has a value which is a float
number_of_solutions has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
fbamodel_id has a value which is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
proteincomparison_id has a value which is a fba_tools.proteincomparison_id
proteincomparison_workspace has a value which is a fba_tools.workspace_name
fbamodel_output_id has a value which is a fba_tools.fbamodel_id
workspace has a value which is a fba_tools.workspace_name
keep_nogene_rxn has a value which is a fba_tools.bool
gapfill_model has a value which is a fba_tools.bool
media_id has a value which is a fba_tools.media_id
media_workspace has a value which is a fba_tools.workspace_name
thermodynamic_constraints has a value which is a fba_tools.bool
comprehensive_gapfill has a value which is a fba_tools.bool
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id
expseries_id has a value which is a fba_tools.expseries_id
expseries_workspace has a value which is a fba_tools.workspace_name
exp_condition has a value which is a string
exp_threshold_percentile has a value which is a float
exp_threshold_margin has a value which is a float
activation_coefficient has a value which is a float
omega has a value which is a float
objective_fraction has a value which is a float
minimum_target_flux has a value which is a float
number_of_solutions has a value which is an int


=end text

=back



=head2 PropagateModelToNewGenomeResults

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
new_fba_ref has a value which is a fba_tools.ws_fba_id
number_gapfilled_reactions has a value which is an int
number_removed_biomass_compounds has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id
new_fba_ref has a value which is a fba_tools.ws_fba_id
number_gapfilled_reactions has a value which is an int
number_removed_biomass_compounds has a value which is an int


=end text

=back



=head2 SimulateGrowthOnPhenotypeDataParams

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
fbamodel_id has a value which is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
phenotypeset_id has a value which is a fba_tools.phenotypeset_id
phenotypeset_workspace has a value which is a fba_tools.workspace_name
phenotypesim_output_id has a value which is a fba_tools.phenotypesim_id
workspace has a value which is a fba_tools.workspace_name
all_reversible has a value which is a fba_tools.bool
feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
fbamodel_id has a value which is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
phenotypeset_id has a value which is a fba_tools.phenotypeset_id
phenotypeset_workspace has a value which is a fba_tools.workspace_name
phenotypesim_output_id has a value which is a fba_tools.phenotypesim_id
workspace has a value which is a fba_tools.workspace_name
all_reversible has a value which is a fba_tools.bool
feature_ko_list has a value which is a reference to a list where each element is a fba_tools.feature_id
reaction_ko_list has a value which is a reference to a list where each element is a fba_tools.reaction_id
custom_bound_list has a value which is a reference to a list where each element is a string
media_supplement_list has a value which is a reference to a list where each element is a fba_tools.compound_id


=end text

=back



=head2 SimulateGrowthOnPhenotypeDataResults

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_phenotypesim_ref has a value which is a fba_tools.ws_phenotypesim_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_phenotypesim_ref has a value which is a fba_tools.ws_phenotypesim_id


=end text

=back



=head2 MergeMetabolicModelsIntoCommunityModelParams

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
fbamodel_id_list has a value which is a reference to a list where each element is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
fbamodel_output_id has a value which is a fba_tools.fbamodel_id
workspace has a value which is a fba_tools.workspace_name
mixed_bag_model has a value which is a fba_tools.bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
fbamodel_id_list has a value which is a reference to a list where each element is a fba_tools.fbamodel_id
fbamodel_workspace has a value which is a fba_tools.workspace_name
fbamodel_output_id has a value which is a fba_tools.fbamodel_id
workspace has a value which is a fba_tools.workspace_name
mixed_bag_model has a value which is a fba_tools.bool


=end text

=back



=head2 MergeMetabolicModelsIntoCommunityModelResults

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_fbamodel_ref has a value which is a fba_tools.ws_fbamodel_id


=end text

=back



=cut

1;