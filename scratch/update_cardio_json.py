import json

# 1. Update exercise_terminology.json
with open('assets/exercise_terminology.json', 'r', encoding='utf-8') as f:
    term_data = json.load(f)

cardio_terms = {
    'Treadmill Walking': {
        'exercise_id': 191,
        'current_name': 'Treadmill Walking',
        'recommended_display_name': 'Treadmill Walking',
        'formal_name': 'Motorized Treadmill Walking',
        'aliases': ['Treadmill Walk', 'Incline Treadmill Walk', 'Incline Walk', 'Treadmill Cardio', 'Cardio Walk', 'Treadmill'],
        'kerala_gym_notes': 'Standard gym warmup and steady-state cardio staple. Set slight incline to protect knees and walk with natural arm cadence.',
        'malayalam_script': 'ട്രെഡ്മിൽ വാക്കിംഗ്',
        'status': 'ADD ALIAS',
        'reason': 'Universal gym cardio exercise.',
        'muscle_group': 'Cardio',
        'equipment': 'Treadmill'
    },
    'Treadmill Running': {
        'exercise_id': 192,
        'current_name': 'Treadmill Running',
        'recommended_display_name': 'Treadmill Running',
        'formal_name': 'Motorized Treadmill Running',
        'aliases': ['Treadmill Run', 'Treadmill Jog', 'Treadmill Sprint', 'Cardio Running', 'Jogging'],
        'kerala_gym_notes': 'High-intensity cardiovascular stamina drill. Warm up with a light walk before dialing up belt velocity.',
        'malayalam_script': 'ട്രെഡ്മിൽ റണ്ണിംഗ്',
        'status': 'ADD ALIAS',
        'reason': 'Universal gym cardio exercise.',
        'muscle_group': 'Cardio',
        'equipment': 'Treadmill'
    },
    'Outdoor Walking': {
        'exercise_id': 193,
        'current_name': 'Outdoor Walking',
        'recommended_display_name': 'Outdoor Walking',
        'formal_name': 'Brisk Outdoor Walking',
        'aliases': ['Morning Walk', 'Brisk Walk', 'Road Walk', 'Walking', 'Evening Walk', 'Outdoor Walk'],
        'kerala_gym_notes': 'Everyday Kerala fitness habit. Brisk walking along road tracks or turf for active recovery and low-impact fat burn.',
        'malayalam_script': 'ഔട്ട്ഡോർ വാക്കിംഗ്',
        'status': 'ADD ALIAS',
        'reason': 'Commonly practiced functional conditioning.',
        'muscle_group': 'Cardio',
        'equipment': 'None'
    },
    'Outdoor Running': {
        'exercise_id': 194,
        'current_name': 'Outdoor Running',
        'recommended_display_name': 'Outdoor Running',
        'formal_name': 'Road & Cross-Country Running',
        'aliases': ['Running', 'Jogging', 'Road Run', 'Track Run', 'Outdoor Jog', 'Sprint'],
        'kerala_gym_notes': 'Cardiovascular road workout. Excellent for building natural leg drive, lung capacity, and mental endurance.',
        'malayalam_script': 'ഔട്ട്ഡോർ റണ്ണിംഗ്',
        'status': 'ADD ALIAS',
        'reason': 'Standard athletic running exercise.',
        'muscle_group': 'Cardio',
        'equipment': 'None'
    },
    'Stationary Cycling': {
        'exercise_id': 195,
        'current_name': 'Stationary Cycling',
        'recommended_display_name': 'Stationary Cycling',
        'formal_name': 'Indoor Stationary Ergometer Cycling',
        'aliases': ['Exercise Bike', 'Spin Bike', 'Gym Cycling', 'Stationary Bike', 'Cycle', 'Spinning'],
        'kerala_gym_notes': 'Low-impact knee-friendly cardio favorite in Kerala gyms. Maintain high cadence with moderate magnetic resistance.',
        'malayalam_script': 'സ്റ്റേഷനറി സൈക്ലിംഗ്',
        'status': 'ADD ALIAS',
        'reason': 'Universal gym machine cardio name.',
        'muscle_group': 'Cardio',
        'equipment': 'Stationary Bike'
    },
    'Elliptical Trainer': {
        'exercise_id': 196,
        'current_name': 'Elliptical Trainer',
        'recommended_display_name': 'Elliptical Trainer',
        'formal_name': 'Elliptical Cross-Trainer',
        'aliases': ['Cross Trainer', 'Elliptical Machine', 'Elliptical Cardio', 'Elliptical', 'Glider'],
        'kerala_gym_notes': "Commonly known as 'Cross Trainer' in local gyms. Smooth zero-impact gliding movement engaging both arms and legs.",
        'malayalam_script': 'എലിപ്റ്റിക്കൽ ട്രെയിനർ',
        'status': 'ADD ALIAS',
        'reason': 'Standard gym equipment cross-trainer.',
        'muscle_group': 'Cardio',
        'equipment': 'Elliptical'
    },
    'Rowing Machine': {
        'exercise_id': 197,
        'current_name': 'Rowing Machine',
        'recommended_display_name': 'Rowing Machine',
        'formal_name': 'Indoor Ergometer Rowing',
        'aliases': ['Rower', 'Ergometer', 'Rowing Erg', 'Concept 2', 'Indoor Rower', 'Rowing'],
        'kerala_gym_notes': 'Demanding full-body stamina exercise. Drive through the legs first, swing hip angle, then pull handle into lower sternum.',
        'malayalam_script': 'റോവിംഗ് മെഷീൻ',
        'status': 'ADD ALIAS',
        'reason': 'Universal gym rowing machine name.',
        'muscle_group': 'Cardio',
        'equipment': 'Rowing Machine'
    },
    'Stair Climber': {
        'exercise_id': 198,
        'current_name': 'Stair Climber',
        'recommended_display_name': 'Stair Climber',
        'formal_name': 'Revolving Stairmaster Climber',
        'aliases': ['Stairmaster', 'Stair Stepper', 'Step Mill', 'Stairs', 'Stepper'],
        'kerala_gym_notes': 'Popular lower body sculpting and calorie-burning cardio machine. Stand upright without bearing weight on console handles.',
        'malayalam_script': 'സ്റ്റെയർ ക്ലൈമ്പർ',
        'status': 'ADD ALIAS',
        'reason': 'Universal gym stair climber machine.',
        'muscle_group': 'Cardio',
        'equipment': 'Stair Machine'
    },
    'Jump Rope': {
        'exercise_id': 199,
        'current_name': 'Jump Rope',
        'recommended_display_name': 'Jump Rope',
        'formal_name': 'Cardiovascular Rope Skipping',
        'aliases': ['Skipping', 'Skipping Rope', 'Speed Rope', 'Rope Jump', 'Skipping Cardio'],
        'kerala_gym_notes': "Almost universally called 'Skipping' in Kerala gyms and sports academies. Jump lightly on the balls of your feet.",
        'malayalam_script': 'ജമ്പ് റോപ്പ് (സ്കിപ്പിംഗ്)',
        'status': 'ADD ALIAS',
        'reason': 'Universal sports conditioning exercise.',
        'muscle_group': 'Cardio',
        'equipment': 'Jump Rope'
    },
    'Jumping Jacks': {
        'exercise_id': 200,
        'current_name': 'Jumping Jacks',
        'recommended_display_name': 'Jumping Jacks',
        'formal_name': 'Calisthenic Jumping Jacks',
        'aliases': ['Star Jumps', 'Jacks', 'Side Straddle Hop', 'Cardio Jacks'],
        'kerala_gym_notes': 'Universal calisthenics warmup and HIIT circuit drill. Land with soft knees to protect joints.',
        'malayalam_script': 'ജമ്പിംഗ് ജാക്ക്സ്',
        'status': 'ADD ALIAS',
        'reason': 'Universal bodyweight cardio movement.',
        'muscle_group': 'Cardio',
        'equipment': 'Bodyweight'
    },
    'High Knees': {
        'exercise_id': 201,
        'current_name': 'High Knees',
        'recommended_display_name': 'High Knees',
        'formal_name': 'High Knee Running in Place',
        'aliases': ['High Knee Run', 'Running High Knees', 'Sprint High Knees', 'Knee Drives'],
        'kerala_gym_notes': 'Athletic sprinting drill used in HIIT and warmup circuits. Pump arms dynamically while driving knees upward.',
        'malayalam_script': 'ഹൈ നീസ്',
        'status': 'ADD ALIAS',
        'reason': 'Universal athletic conditioning exercise.',
        'muscle_group': 'Cardio',
        'equipment': 'Bodyweight'
    }
}

for k, v in cardio_terms.items():
    term_data[k] = v

# Enhance Mountain Climber & Burpee aliases with 'cardio' and 'hiit'
if 'Mountain Climber' in term_data:
    aliases = term_data['Mountain Climber']['aliases']
    for a in ['Mountain Climbers', 'Cardio Climber', 'HIIT Climber', 'Cardio']:
        if a not in aliases:
            aliases.append(a)

if 'Burpee' in term_data:
    aliases = term_data['Burpee']['aliases']
    for a in ['Burpees', 'HIIT Burpee', 'Cardio Burpee', 'Cardio']:
        if a not in aliases:
            aliases.append(a)

with open('assets/exercise_terminology.json', 'w', encoding='utf-8') as f:
    json.dump(term_data, f, indent=2, ensure_ascii=False)
print(f'Updated assets/exercise_terminology.json (Total entries: {len(term_data)})')

# 2. Update exercise_demonstrations.json
with open('assets/exercise_demonstrations.json', 'r', encoding='utf-8') as f:
    demo_data = json.load(f)

demo_cardio = {
    'Treadmill Walking': {
        'exercise_id': 191,
        'name': 'Treadmill Walking',
        'slug': 'treadmill_walking',
        'muscle_group': 'Cardio',
        'equipment': 'Treadmill',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/treadmill_walking.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Clip safety tether', 'Natural arm swing', 'Maintain upright posture']
    },
    'Treadmill Running': {
        'exercise_id': 192,
        'name': 'Treadmill Running',
        'slug': 'treadmill_running',
        'muscle_group': 'Cardio',
        'equipment': 'Treadmill',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/treadmill_running.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Midfoot landing cadence', 'Relaxed shoulders', 'Even stride turnover']
    },
    'Outdoor Walking': {
        'exercise_id': 193,
        'name': 'Outdoor Walking',
        'slug': 'outdoor_walking',
        'muscle_group': 'Cardio',
        'equipment': 'None',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/outdoor_walking.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Brisk 5 km/h pace', 'Heel-to-toe roll', 'Eyes on the horizon']
    },
    'Outdoor Running': {
        'exercise_id': 194,
        'name': 'Outdoor Running',
        'slug': 'outdoor_running',
        'muscle_group': 'Cardio',
        'equipment': 'None',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/outdoor_running.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Dynamic warmup first', 'Aerobic conversational pace', 'Smooth forward propulsion']
    },
    'Stationary Cycling': {
        'exercise_id': 195,
        'name': 'Stationary Cycling',
        'slug': 'stationary_cycling',
        'muscle_group': 'Cardio',
        'equipment': 'Stationary Bike',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/stationary_cycling.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Proper saddle height', '70-90 RPM cadence', 'Controlled breathing']
    },
    'Elliptical Trainer': {
        'exercise_id': 196,
        'name': 'Elliptical Trainer',
        'slug': 'elliptical_trainer',
        'muscle_group': 'Cardio',
        'equipment': 'Elliptical',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/elliptical_trainer.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Push and pull handles', 'Heels in full contact', 'Upright spine']
    },
    'Rowing Machine': {
        'exercise_id': 197,
        'name': 'Rowing Machine',
        'slug': 'rowing_machine',
        'muscle_group': 'Cardio',
        'equipment': 'Rowing Machine',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/rowing_machine.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Drive with legs first', 'Torso swing 1 oclock', 'Smooth recovery slide']
    },
    'Stair Climber': {
        'exercise_id': 198,
        'name': 'Stair Climber',
        'slug': 'stair_climber',
        'muscle_group': 'Cardio',
        'equipment': 'Stair Machine',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/stair_climber.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Full foot plant on step', 'Light touch on rails', 'Glute drive']
    },
    'Jump Rope': {
        'exercise_id': 199,
        'name': 'Jump Rope',
        'slug': 'jump_rope',
        'muscle_group': 'Cardio',
        'equipment': 'Jump Rope',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/jump_rope.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Rotate with wrists', '1-2 inch hop', 'Land softly on balls of feet']
    },
    'Jumping Jacks': {
        'exercise_id': 200,
        'name': 'Jumping Jacks',
        'slug': 'jumping_jacks',
        'muscle_group': 'Cardio',
        'equipment': 'Bodyweight',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/jumping_jacks.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Arms overhead', 'Feet shoulder width', 'Rhythmic continuous tempo']
    },
    'High Knees': {
        'exercise_id': 201,
        'name': 'High Knees',
        'slug': 'high_knees',
        'muscle_group': 'Cardio',
        'equipment': 'Bodyweight',
        'has_video': False,
        'media_type': 'image',
        'image_fallback_path': 'assets/images/exercises/high_knees.jpg',
        'duration_seconds': 10,
        'license': 'CC BY 4.0',
        'attribution': 'RepTrack Cardio Collection',
        'demonstration_cues': ['Drive knees to hip level', 'Quick ground contact', 'Opposite arm pump']
    }
}

for k, v in demo_cardio.items():
    demo_data[k] = v

with open('assets/exercise_demonstrations.json', 'w', encoding='utf-8') as f:
    json.dump(demo_data, f, indent=2)
print(f'Updated assets/exercise_demonstrations.json (Total entries: {len(demo_data)})')
