// Optional Godot 4.6 iOS static plugin. Requires ARC and iOS 13+.
// Source only: not compiled or device-tested on the Windows development host.
#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "core/variant/variant.h"
#import <CoreHaptics/CoreHaptics.h>
#import <Foundation/Foundation.h>
#include <cmath>

class NeonPotHaptics : public Object {
	GDCLASS(NeonPotHaptics, Object);
	CHHapticEngine *__strong engine = nil;
	NSMutableArray<id<CHHapticPatternPlayer>> *__strong players = nil;

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("is_supported"), &NeonPotHaptics::is_supported);
		ClassDB::bind_method(D_METHOD("play_transients", "times", "intensities", "sharpness"), &NeonPotHaptics::play_transients);
		ClassDB::bind_method(D_METHOD("stop"), &NeonPotHaptics::stop);
	}

public:
	bool is_supported() const {
		return [CHHapticEngine capabilitiesForHardware].supportsHaptics;
	}

	bool play_transients(const PackedFloat32Array &times, const PackedFloat32Array &intensities, double sharpness) {
		if (!is_supported() || times.is_empty() || times.size() != intensities.size() || times.size() > 8 || !std::isfinite(sharpness)) {
			return false;
		}
		NSError *error = nil;
		if (!engine) {
			engine = [[CHHapticEngine alloc] initAndReturnError:&error];
			if (!engine || error) { engine = nil; return false; }
			engine.playsHapticsOnly = YES; // Never take over the game's music/audio session.
			engine.autoShutdownEnabled = YES;
			players = [NSMutableArray array];
		}
		// Starting an already running engine is supported. New players/patterns are
		// created after interruptions or resets, so no stale player is reused.
		if (![engine startAndReturnError:&error]) { return false; }
		NSMutableArray<CHHapticEvent *> *events = [NSMutableArray array];
		for (int i = 0; i < times.size(); ++i) {
			if (!std::isfinite(times[i]) || !std::isfinite(intensities[i]) || times[i] < 0 || times[i] > 0.5) { return false; }
			float intensity = CLAMP(intensities[i], 0.0f, 1.0f);
			if (intensity <= 0) { continue; }
			CHHapticEventParameter *weight = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:intensity];
			CHHapticEventParameter *edge = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:CLAMP(sharpness, 0.0, 1.0)];
			[events addObject:[[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient parameters:@[weight, edge] relativeTime:times[i]]];
		}
		if (events.count == 0) { return true; }
		CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:events parameters:@[] error:&error];
		if (!pattern || error) { return false; }
		id<CHHapticPatternPlayer> player = [engine createPlayerWithPattern:pattern error:&error];
		if (!player || error || ![player startAtTime:CHHapticTimeImmediate error:&error]) { return false; }
		// The GDScript scheduler sends short serialized impulses. Keep recent players
		// so an explicit scene/focus cancellation can stop all still-active impulses.
		[players addObject:player];
		if (players.count > 8) { [players removeObjectAtIndex:0]; }
		return true;
	}

	void stop() {
		for (id<CHHapticPatternPlayer> player in players) {
			[player stopAtTime:CHHapticTimeImmediate error:nil];
		}
		[players removeAllObjects];
	}

	~NeonPotHaptics() {
		stop();
		[engine stopWithCompletionHandler:nil];
		engine = nil;
		players = nil;
	}
};

static NeonPotHaptics *neon_pot_haptics = nullptr;

void initialize_neon_pot_haptics() {
	if (neon_pot_haptics) { return; }
	ClassDB::register_class<NeonPotHaptics>();
	neon_pot_haptics = memnew(NeonPotHaptics);
	Engine::get_singleton()->add_singleton(Engine::Singleton("NeonPotHaptics", neon_pot_haptics));
}

void deinitialize_neon_pot_haptics() {
	if (!neon_pot_haptics) { return; }
	Engine::get_singleton()->remove_singleton("NeonPotHaptics");
	memdelete(neon_pot_haptics);
	neon_pot_haptics = nullptr;
}
