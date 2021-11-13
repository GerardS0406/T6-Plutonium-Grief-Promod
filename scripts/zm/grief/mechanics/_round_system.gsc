#include maps/mp/zombies/_zm_utility;
#include maps/mp/zombies/_zm;
#include common_scripts/utility;
#include scripts/zm/grief/gametype/_pregame;
#include scripts/zm/grief/gametype/_hud;

generate_storage_maps()
{
	key_list = "str:player_name|str:team_name|bool:is_perm|bool:is_banned";
	key_names = "value_types|keys";
	scripts/zm/grief/gametype_modules/_gamerules::generate_map( "grief_preset_teams", key_list, key_names );
	key_list = "allies:B:false:0|axis:A:false:0"; //|team3:C:false:0|team4:D:false:0|team5:E:false:0|team6:F:false:0|team7:G:false:0|team8:H:false:0
	key_names = "team|e_team|alive|score";
	scripts/zm/grief/gametype_modules/_gamerules::generate_map( "encounters_teams", key_list, key_names );

	level.team_index_grief[ "allies" ] = 0;
	level.team_index_grief[ "axis" ] = 1;
	team_count = getGametypeSetting( "teamCount" );
	for ( teamindex = 2; teamindex <= team_count; teamIndex++ )
	{
		level.teams[ "team" + teamindex ] = "team" + teamIndex;
		level.team_index_grief[ "team" + teamindex ] = teamIndex;
	}
}

grief_save_loadouts()
{
	while ( true )
	{
		flag_wait( "spawn_zombies" );
		players = getPlayers();
		foreach ( player in players )
		{
			if ( is_player_valid( player ) )
			{
				player scripts/zm/grief/mechanics/loadout/_weapons::grief_loadout_save();
			}
		}
		wait 1;
	}
}

grief_team_forfeit()
{
	if ( getDvarInt( "grief_testing" ) == 1 )
	{
		return false;
	}
	if ( ( getPlayers( "axis" ).size == 0 ) || ( getPlayers( "allies" ).size == 0 ) )
	{
		return true;
	}
	return false;
}

check_for_match_winner( winner )
{
	if ( level.data_maps[ "encounters_teams" ][ "score" ][ level.team_index_grief[ winner ] ] == level.grief_gamerules[ "scorelimit" ] )
	{
		return true;
	}
	if ( grief_team_forfeit() )
	{
		return true;
	}
	return false;
}

match_end( winner )
{
	level.gamemodulewinningteam = level.data_maps[ "encounters_teams" ][ "eteam" ][ level.team_index_grief[ winner ] ];
	players = getPlayers();
	for ( i = 0; i < players.size; i++ )
	{
		players[ i ] freezecontrols( 1 );
		if ( players[ i ].team == winner )
		{
			players[ i ] thread maps/mp/zombies/_zm_audio_announcer::leaderdialogonplayer( "grief_won" );
			players[ i ].pers[ "wins" ]++;
		}
		else 
		{
			players[ i ] thread maps/mp/zombies/_zm_audio_announcer::leaderdialogonplayer( "grief_lost" );
			players[ i ].pers[ "losses" ]++;
		}
	}
	level._game_module_game_end_check = undefined;
	maps/mp/gametypes_zm/_zm_gametype::track_encounters_win_stats( level.gamemodulewinningteam );
	level notify( "end_game" );
}

round_winner()
{
	winner = level.predicted_round_winner;
	level.data_maps[ "encounters_teams" ][ "score" ][ level.team_index_grief[ winner ] ]++;
	level.server_hudelems[ "grief_score_" + winner ].hudelem SetValue( level.data_maps[ "encounters_teams" ][ "score" ][ level.team_index_grief[ winner ] ] );
	setTeamScore( winner, level.data_maps[ "encounters_teams" ][ "score" ][ level.team_index_grief[ winner ] ] );
	if ( check_for_match_winner( winner ) )
	{
		match_end( winner );
		return;
	}
	start_new_round( false );
}

round_restart()
{
	start_new_round( true );
}

check_for_surviving_team()
{
	level endon( "end_game" );
	new_round = false;
	while ( 1 )
	{
		while ( !flag( "spawn_zombies" ) || new_round )
		{
			if ( flag( "spawn_zombies" ) )
			{
				break;
			}
			wait 1;
		}
		new_round = false;
		if ( count_alive_teams() == 0 )
		{
			new_round = true;
			round_restart();
		}
		else if ( count_alive_teams() == 1 && isDefined( level.predicted_round_winner ) )
		{
			wait level.grief_gamerules[ "suicide_check" ];
			if ( count_alive_teams() == 0 )
			{
				new_round = true;
				round_restart();
				wait 0.05;
				continue;
			}
			new_round = true;
			round_winner();
		}
		wait 0.05;
	}
}

count_alive_teams()
{
	players = getPlayers();
	teams = [];
	alive_teams = 0;
	level.predicted_round_winner = undefined;
	foreach ( team in level.teams )
	{
		teams[ team ] = [];
		teams[ team ][ "alive_players" ] = 0;
	}
	for ( i = 0; i < players.size; i++ )
	{
		foreach ( team in level.teams )
		{
			if ( is_player_valid( players[ i ] ) )
			{
				if ( players[ i ].team == team )
				{
					teams[ team ][ "alive_players" ]++;
				}
			}
			if ( teams[ team ][ "alive_players" ] > 0 )
			{
				alive_teams++;
				level.predicted_round_winner = team;
			}
		}
	}
	return alive_teams;
}

zgrief_main_override()
{
	flag_wait( "initial_blackscreen_passed" );
	match_start();
	players = getPlayers();
	foreach ( player in players )
	{
		player.is_hotjoin = 0;
	}
	wait 1;
}

match_start()
{
	while ( flag( "in_pregame" ) )
	{
		wait 0.05;
	}
	freeze_all_players_controls();
	//level thread maps/mp/zombies/_zm_audio::change_zombie_music( "round_start" );
	flag_clear( "spawn_zombies" );
	level thread scripts/zm/grief/mechanics/_zombies::zombie_spawning();
	flag_set( "match_start" );
	flag_set( "first_round" );
	level.rounds_played = 0;
	scripts/zm/grief/gametype/_hud::hud_init(); //part of _hud module
	flag_set( "timer_pause" );
	setdvar( "ui_scorelimit", level.grief_gamerules[ "scorelimit" ] );
	makeDvarServerInfo( "ui_scorelimit" );
	level thread timed_rounds(); //3
	start_new_round( false ); //2
	level thread grief_save_loadouts();
	level thread check_for_surviving_team(); //1
	flag_clear( "first_round" );
}

start_new_round( is_restart )
{
	if ( flag( "spawn_zombies" ) )
	{
		flag_clear( "spawn_zombies" );
	}
	level thread kill_all_zombies();
	level.new_round_started = true;
	scripts/zm/grief/mechanics/_zombies::set_zombie_power_level( level.grief_gamerules[ "zombie_power_level_start" ] );
	if ( !flag( "timer_pause" ) )
	{
		flag_set( "timer_pause" );
	}
	if ( !flag( "first_round" ) )
	{
		//level thread maps/mp/zombies/_zm_audio::change_zombie_music( "round_end" );
		flag_set( "spawn_players" );
		respawn_players();
	}
	if ( is_true( is_restart ) )
	{
		level thread grief_reset_message();
	}
	else 
	{
		if ( !flag( "first_round" ) )
		{
			freeze_all_players_controls();
		}
		round_change_hud_text();
		round_change_hud_timer_elem();
		wait level.grief_gamerules[ "next_round_time" ];
		level.rounds_played++;
	}
	scripts/zm/grief/mechanics/_griefing::reset_players_last_griefed_by();
	unfreeze_all_players_controls();
	give_points_on_restart_and_round_change();
	if ( flag( "timer_pause" ) )
	{
		flag_clear( "timer_pause" );
	}
	wait level.grief_gamerules[ "round_zombie_spawn_delay" ];
	//level thread maps/mp/zombies/_zm_audio::change_zombie_music( "round_start" );
	flag_clear( "spawn_players" );
	if ( !flag( "spawn_zombies" ) )
	{
		flag_set( "spawn_zombies" );
	}
	level.new_round_started = false;
}

give_points_on_restart_and_round_change()
{
	players = getPlayers();
	foreach ( player in players )
	{
		if ( self.score < level.grief_gamerules[ "round_restart_points" ] )
		{
			self.score = level.grief_gamerules[ "round_restart_points" ];
		}
	}
}

timed_rounds() //checked matches cerberus output
{
	level endon( "end_game" );
	timelimit_in_seconds = int( level.grief_gamerules[ "timelimit" ] * 60 );
	time_left = parse_minutes( to_mins( timelimit_in_seconds ) );
	//BEG Overflow fix
	level.overflow_elem = maps/mp/gametypes_zm/_hud_util::createServerFontString("default",1.5);
	level.overflow_elem setText("xTUL"); //dont remove text here                  
	level.overflow_elem.alpha = 0;
	//END Overflow fix
	while ( true )
	{
		if ( flag( "timer_pause" ) )
		{
			level.server_hudelems[ "timer" ].hudelem.alpha = 0;
			while ( flag( "timer_pause" ) )
			{
				wait 1;
			}
			zombie_spawn_delay = level.grief_gamerules[ "round_zombie_spawn_delay" ];
			level.server_hudelems[ "timer" ].hudelem.alpha = 1;
			while ( zombie_spawn_delay > 0 )
			{
				time_left = parse_minutes( to_mins( zombie_spawn_delay ) );
				timeleft_text = time_left[ "minutes" ] + ":" + time_left[ "seconds" ];
				//HUDELEM_STORE_TEXT( "timer", timeleft_text );
				level.server_hudelems[ "timer" ].hudelem HUDELEM_SET_TEXT( timeleft_text );
				wait 1;
				zombie_spawn_delay--;
			}
			waittillframeend;
			timelimit_in_seconds = int( level.grief_gamerules[ "timelimit" ] * 60 );
			time_left = parse_minutes( to_mins( timelimit_in_seconds ) );
			timeleft_text = time_left[ "minutes" ] + ":" + time_left[ "seconds" ];
			//HUDELEM_STORE_TEXT( "timer", timeleft_text );
			level.server_hudelems[ "timer" ].hudelem HUDELEM_SET_TEXT( timeleft_text );
		}
		time_left = parse_minutes( to_mins( timelimit_in_seconds ) );
		timeleft_text = time_left[ "minutes" ] + ":" + time_left[ "seconds" ];
		//HUDELEM_STORE_TEXT( "timer", timeleft_text );
		level.server_hudelems[ "timer" ].hudelem HUDELEM_SET_TEXT( timeleft_text );
		wait 1;
		timelimit_in_seconds--;
		if ( ( timelimit_in_seconds % level.zombies_powerup_time ) == 0 )
		{
			if ( level.script == "zm_transit" )
			{
				play_sound_2d( "evt_nomans_warning" );
			}
			else 
			{
				level thread maps/mp/zombies/_zm_audio::change_zombie_music( "round_start" );
			}
			scripts/zm/grief/mechanics/_zombies::powerup_zombies();
			level.overflow_elem ClearAllTextAfterHudElem();
			level.server_hudelems[ "timer" ].hudelem destroy();
			level.server_hudelems[ "timer" ].hudelem = [[ level.server_hudelem_funcs[ "timer" ] ]]();
		}
	}
}

parse_minutes( start_time )
{
	time = [];
	keys = strtok( start_time, ":" );
	time[ "hours" ] = keys[ 0 ];
	time[ "minutes" ] = keys[ 1 ];
	time[ "seconds" ] = keys[ 2 ];
	return time;
}

kill_all_zombies()
{
	zombies = getaispeciesarray( level.zombie_team, "all" );
	for ( i = 0; i < zombies.size; i++ )
	{
		if ( isDefined( zombies[ i ] ) && isAlive( zombies[ i ] ) )
		{
			zombies[ i ] dodamage( zombies[ i ].health + 666, zombies[ i ].origin );
		}
	}
}

all_surviving_players_invulnerable()
{
	players = getPlayers();
	foreach ( player in players )
	{
		if ( is_player_valid( player ) )
		{
			player enableInvulnerability();
		}
	}
}

all_surviving_players_vulnerable()
{
	players = getPlayers();
	foreach ( player in players )
	{
		if ( is_player_valid( player ) )
		{
			player disableInvulnerability();
		}
	}
}

respawn_players()
{
	players = getPlayers();
	foreach ( player in players )
	{
		player [[ level.spawnplayer ]]();
	}
}

freeze_all_players_controls()
{
	players = getPlayers();
	foreach ( player in players )
	{
		player freezeControls( 1 );
	}
}

unfreeze_all_players_controls()
{
	players = getPlayers();
	foreach ( player in players )
	{
		player freezeControls( 0 );
	}
}

grief_reset_message()
{
	msg = &"ZOMBIE_GRIEF_RESET";
	// players = getPlayers();
	// foreach ( player in players )
	// {
	// 	player thread scripts/zm/grief/gametype/_grief_hud::show_grief_hud_msg( msg );
	// }
	level thread maps/mp/zombies/_zm_audio_announcer::leaderdialog( "grief_restarted" );
}