shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ── 8 Gerstner waves: (dir_x, dir_z, amplitude, wavelength) ──────────────────
uniform vec4 wave_a = vec4( 1.00,  0.00, 0.38, 22.0);
uniform vec4 wave_b = vec4( 0.65,  0.76, 0.24, 16.0);
uniform vec4 wave_c = vec4(-0.22,  0.98, 0.14, 11.0);
uniform vec4 wave_d = vec4( 0.85, -0.53, 0.09,  8.0);
uniform vec4 wave_e = vec4( 0.57,  0.82, 0.05,  5.0);
uniform vec4 wave_f = vec4(-0.81,  0.59, 0.04,  3.8);
uniform vec4 wave_g = vec4( 0.31, -0.95, 0.03,  2.7);
uniform vec4 wave_h = vec4( 0.93,  0.37, 0.02,  1.8);

uniform float steepness       : hint_range(0.0, 1.0) = 0.38;
uniform float wave_time       = 0.0;
uniform float chop_amp        : hint_range(0.0, 1.0) = 0.10;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.65;

uniform vec4  color_deep    : source_color = vec4(0.02, 0.18, 0.22, 1.0);
uniform vec4  color_shallow : source_color = vec4(0.05, 0.52, 0.38, 1.0);
uniform vec4  color_foam    : source_color = vec4(0.87, 0.93, 0.97, 1.0);
uniform float foam_height   : hint_range(0.0, 2.0) = 0.58;  // ~65% of max wave height

// SSS — backlit translucency through thin wave crests
uniform vec4  sss_color : source_color = vec4(0.04, 0.68, 0.35, 1.0);
uniform float sss_str   : hint_range(0.0, 1.0) = 1.0;

// Caustics — animated bright patches from refracted sunlight
uniform float caustic_str  : hint_range(0.0, 2.0) = 0.75;

// Screen-space refraction + depth fog
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture  : hint_depth_texture,  repeat_disable, filter_nearest;
uniform float refraction_str     : hint_range(0.0, 0.08) = 0.022;
// Clarity: 0 = opaque/deep-looking, 1 = crystal-clear/shallow-looking
uniform float clarity            : hint_range(0.0, 1.0)  = 0.45;
// Depth at which underwater fog begins (metres below surface)
uniform float depth_fog_start : hint_range(0.0, 20.0)  = 0.5;
// Depth at which the fog reaches full density
uniform float depth_fog_end   : hint_range(0.0, 200.0) = 12.0;

// LOD: each ring only renders within its distance band
uniform float lod_min_dist = 0.0;
uniform float lod_max_dist = 1.0e9;

varying float v_wave_y;
varying vec3  v_world_xz_t;
varying float v_cam_dist;
varying float v_geom_normal_y;  // geometric (pre-normal-map) normal Y for crest detection


// ── Noise ─────────────────────────────────────────────────────────────────────

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(_hash(i),                 _hash(i + vec2(1.0, 0.0)), u.x),
		mix(_hash(i + vec2(0.0, 1.0)), _hash(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float _fbm(vec2 p) {
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * _vnoise(p);
		p  = rot * p * 2.0 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float _wfbm(vec2 p) {
	vec2 q = vec2(_fbm(p), _fbm(p + vec2(5.2, 1.3)));
	return _fbm(p + 2.5 * q);
}

// ── Stochastic FBM (Inigo Quilez technique) ───────────────────────────────────
// Divides the plane into large random cells. Each cell samples FBM at a unique
// random rotation and offset, blended smoothly at boundaries.
// Result: no global period — neighboring cells look completely unrelated.

mat2 _rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

vec2 _hash2v(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// cell_scale controls how large each random cell is in world units (1/cell_scale).
float _sfbm(vec2 p, float cell_scale) {
	vec2 cp = p * cell_scale;
	vec2 ci = floor(cp);
	vec2 cf = fract(cp);
	vec2 u  = cf * cf * (3.0 - 2.0 * cf);  // smoothstep blend

	vec2 h00 = _hash2v(ci);
	vec2 h10 = _hash2v(ci + vec2(1.0, 0.0));
	vec2 h01 = _hash2v(ci + vec2(0.0, 1.0));
	vec2 h11 = _hash2v(ci + vec2(1.0, 1.0));

	float n00 = _fbm(_rot2(h00.x * 6.28318) * p + h00 * 47.3);
	float n10 = _fbm(_rot2(h10.x * 6.28318) * p + h10 * 47.3);
	float n01 = _fbm(_rot2(h01.x * 6.28318) * p + h01 * 47.3);
	float n11 = _fbm(_rot2(h11.x * 6.28318) * p + h11 * 47.3);

	return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}


// ── Gerstner wave ─────────────────────────────────────────────────────────────

vec3 _gerstner(vec4 wave, float phase, vec2 xz, float t,
               inout vec3 tan, inout vec3 bin) {
	vec2  d = normalize(wave.xy);
	float k = 6.28318 / wave.w;
	float c = sqrt(9.8 / k);
	float a = wave.z;
	float q = steepness;
	float f = k * (dot(d, xz) - c * t) + phase;

	tan += vec3(-q * d.x * d.x * a * k * sin(f),
	             d.x          * a * k * cos(f),
	            -q * d.x * d.y * a * k * sin(f));
	bin += vec3(-q * d.x * d.y * a * k * sin(f),
	             d.y          * a * k * cos(f),
	            -q * d.y * d.y * a * k * sin(f));

	return vec3(q * a * d.x * cos(f),
	                a * sin(f),
	            q * a * d.y * cos(f));
}


void vertex() {
	vec2  wxz    = VERTEX.xz + MODEL_MATRIX[3].xz;
	vec2  cam_xz = INV_VIEW_MATRIX[3].xz;
	float t      = wave_time;

	// Three independent phase fields — different noise seeds so wave crests from
	// different trains can't all co-locate and lock into a visible grid.
	float pn1 = _vnoise(wxz * 0.025)                  * 3.2 + _vnoise(wxz * 0.008)                  * 2.8;
	float pn2 = _vnoise(wxz * 0.025 + vec2(4.1, 7.3)) * 3.2 + _vnoise(wxz * 0.008 + vec2(4.1, 7.3)) * 2.8;
	float pn3 = _vnoise(wxz * 0.031 + vec2(9.7, 2.5)) * 2.8 + _vnoise(wxz * 0.011 + vec2(3.6, 6.8)) * 2.4;

	vec3 tan = vec3(1.0, 0.0, 0.0);
	vec3 bin = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);
	disp += _gerstner(wave_a, pn1 * 1.0, wxz, t, tan, bin);
	disp += _gerstner(wave_b, pn2 * 0.8, wxz, t, tan, bin);
	disp += _gerstner(wave_c, pn3 * 1.2, wxz, t, tan, bin);
	disp += _gerstner(wave_d, pn1 * 0.6, wxz, t, tan, bin);
	disp += _gerstner(wave_e, pn2 * 1.4, wxz, t, tan, bin);
	disp += _gerstner(wave_f, pn3 * 0.9, wxz, t, tan, bin);
	// wave_g (2.7 m) and wave_h (1.8 m) are near/below the Nyquist limit of the
	// inner ring's 0.8 m vertex spacing — they alias as geometry, live in the normal map.

	// Four-scale FBM chop — each scale at a unique frequency, direction and speed
	// so no single tile scale dominates.
	float chop = 0.0;
	chop += (_wfbm(wxz * 0.09 + vec2( t*0.03,  t*0.02))              - 0.5) * 0.50;
	chop += (_fbm( wxz * 0.22 + vec2(-t*0.05,  t*0.06) + vec2(2.3, 5.5)) - 0.5) * 0.28;
	chop += (_fbm( wxz * 0.55 + vec2( t*0.09, -t*0.07) + vec2(7.1, 1.3)) - 0.5) * 0.14;
	chop += (_vnoise(wxz * 1.30 + vec2(-t*0.13, t*0.10) + vec2(4.7, 9.2)) - 0.5) * 0.08;
	disp.y += chop * chop_amp;

	// Lateral (XZ) FBM displacement — physically shifts vertices sideways so
	// Gerstner crests can't stay locked on a regular repeating grid.
	vec2 lat = vec2(
		_wfbm(wxz * 0.10 + vec2( t*0.028,  t*0.019) + vec2(1.3, 7.6)),
		_wfbm(wxz * 0.10 + vec2(-t*0.033,  t*0.024) + vec2(5.4, 2.3))
	) - 0.5;
	disp.x += lat.x * chop_amp * 0.8;
	disp.z += lat.y * chop_amp * 0.8;

	VERTEX  += disp;

	float normal_flatness = clamp(lod_min_dist / 200.0, 0.0, 1.0);
	vec3 geom_n = normalize(mix(normalize(cross(bin, tan)), vec3(0.0, 1.0, 0.0), normal_flatness));
	vec3 geom_t = normalize(mix(normalize(tan),             vec3(1.0, 0.0, 0.0), normal_flatness));
	vec3 geom_b = normalize(mix(normalize(bin),             vec3(0.0, 0.0, 1.0), normal_flatness));
	NORMAL   = geom_n;
	TANGENT  = geom_t;
	BINORMAL = geom_b;

	v_wave_y         = disp.y;
	v_world_xz_t     = vec3(VERTEX.xz + MODEL_MATRIX[3].xz, t);
	v_cam_dist       = length(wxz - cam_xz);
	v_geom_normal_y  = geom_n.y;  // 1.0 = flat, <1 = tilted/steep
}


void fragment() {
	if (v_cam_dist < lod_min_dist * 0.98) { discard; }
	if (v_cam_dist > lod_max_dist)        { discard; }

	vec2  wxz = v_world_xz_t.xy;
	float t   = v_world_xz_t.z;

	// Per-pixel world-space footprint — geometrically correct LOD that doesn't
	// shift when the camera translates (unlike a camera-distance heuristic).
	float eps       = clamp(max(fwidth(wxz.x), fwidth(wxz.y)) * 2.0, 0.3, 5.0);
	float dist_fade = 1.0 - smoothstep(0.4, 2.5, eps);

	// Multi-scale detail using stochastic FBM for the coarse layers (no global period)
	// and plain FBM for fine layers (high-freq detail tiles fast enough to be invisible).
	#define DETAIL(p) ( \
		_sfbm((p) + vec2( t*0.030,  t*0.020), 0.022) * 0.50 + \
		_sfbm((p) + vec2(-t*0.048,  t*0.038) + vec2(3.3, 7.7), 0.038) * 0.26 + \
		_fbm( (p) * 1.10  + vec2( t*0.110, -t*0.080) + vec2(1.5, 4.2)) * (0.16 * dist_fade) + \
		_vnoise((p) * 2.80 + vec2(-t*0.180,  t*0.140) + vec2(8.3, 2.1)) * (0.08 * dist_fade) )

	float dx = (DETAIL(wxz + vec2(eps, 0.0)) - DETAIL(wxz - vec2(eps, 0.0))) / (2.0 * eps);
	float dz = (DETAIL(wxz + vec2(0.0, eps)) - DETAIL(wxz - vec2(0.0, eps))) / (2.0 * eps);
	NORMAL_MAP       = normalize(vec3(-dx, -dz, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = detail_strength * (0.5 + dist_fade * 0.5);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float crest_t = smoothstep(0.38, 0.62, v_wave_y);

	vec2  ref_uv = SCREEN_UV + NORMAL.xy * refraction_str;
	float surf_y = MODEL_MATRIX[3].y + v_wave_y;

	// Depth check: if the refracted UV points at geometry above the ocean surface
	// (ground, hull, player) snap back to the unrefracted UV so above-water objects
	// are never warped into the water by the normal offset.
	// Godot 4 / Vulkan: NDC z is [0,1] — pass depth directly, no * 2.0 - 1.0.
	float raw_d   = texture(depth_texture, ref_uv).r;
	vec4  vp      = INV_PROJECTION_MATRIX * vec4(ref_uv * 2.0 - 1.0, raw_d, 1.0);
	vp           /= vp.w;
	float world_y = (INV_VIEW_MATRIX * vec4(vp.xyz, 1.0)).y;
	if (world_y > surf_y) {
		ref_uv  = SCREEN_UV;
		raw_d   = texture(depth_texture, SCREEN_UV).r;
		vp      = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_d, 1.0);
		vp     /= vp.w;
		world_y = (INV_VIEW_MATRIX * vec4(vp.xyz, 1.0)).y;
	}
	vec3 refracted = texture(screen_texture, ref_uv).rgb;

	// Depth fog: linear gradient from depth_fog_start to depth_fog_end metres below surface.
	float depth_m = max(0.0, surf_y - world_y);
	float fog_t   = smoothstep(depth_fog_start, depth_fog_end, depth_m);
	refracted     = mix(refracted, color_deep.rgb * 0.12, fog_t);

	// Flat clarity tint on top (shifts overall colour without depth dependency).
	float tint_str = mix(0.45, 0.08, clarity);
	refracted      = mix(refracted, color_deep.rgb * 0.55, tint_str);
	vec3  water_col = mix(color_deep.rgb, color_shallow.rgb, fresnel);
	float opacity   = mix(0.72, 0.22, clarity) + fresnel * 0.28;
	vec3  col       = mix(refracted, water_col, clamp(opacity, 0.0, 1.0));

	// Wave-cavity ambient occlusion — troughs slightly darker to suggest depth.
	float wave_ao = smoothstep(-0.65, 0.55, v_wave_y);
	col *= mix(0.72, 1.0, wave_ao);

	// Foam: purely stochastic — NOT gated by Gerstner wave height.
	// wave_gate was the cause of the grid: it filtered the stochastic field
	// through the periodic Gerstner maxima, re-introducing the period.
	// Instead, drive foam entirely from two stochastic FBM fields at different
	// cell scales; their product is sparse and has zero repeating period.
	// _sfbm with bare wxz input: cell_scale 0.018 → cells ~55m wide — correct scale.
	// FBM values [0, ~0.94], mean ~0.47; product mean ~0.22, *4 mean ~0.88.
	// Threshold 1.85–2.15 selects the top ~5–8% of the distribution.
	float fn_a       = _sfbm(wxz + vec2( t*0.022,  t*0.016),              0.018);
	float fn_b       = _sfbm(wxz + vec2(-t*0.019,  t*0.025) + vec2(6.3, 2.1), 0.028);
	float foam_field = smoothstep(1.85, 2.15, fn_a * fn_b * 4.0);
	float steep_f    = smoothstep(0.90, 0.70, v_geom_normal_y);
	float foam       = foam_field * (0.3 + steep_f * 0.7);
	col = mix(col, color_foam.rgb, clamp(foam, 0.0, 1.0));

	// Fake caustics — same sparse-product trick, finer spatial scale (~3 m features).
	// wxz*0.30 with cell_scale 0.040 → cells ~83 m wide in world space.
	// product*4.5 mean ≈ 1.0; threshold 1.75–2.05 selects top ~5–8%.
	float ca      = _sfbm(wxz * 0.30 + vec2( t*0.060,  t*0.042), 0.040);
	float cb      = _sfbm(wxz * 0.30 + vec2(-t*0.052,  t*0.065) + vec2(4.1, 2.3), 0.030);
	float caustic = smoothstep(1.75, 2.05, ca * cb * 4.5)
	              * (0.3 + 0.7 * crest_t)    // stronger on wave crests
	              * (1.0 - fresnel * 0.6);   // fades at grazing angles
	col += caustic * caustic_str * vec3(0.82, 1.05, 1.25);

	ALBEDO    = col;
	ROUGHNESS = mix(0.12, 0.30, fresnel);
	METALLIC  = 0.0;
	SPECULAR  = 0.85;

	// BACKLIGHT: Godot multiplies this by the back-face lighting internally,
	// so it only appears when light hits from the opposite side of the surface.
	// No manual crest_t modulation needed — the pipeline handles angle dependency.
	BACKLIGHT = sss_color.rgb * sss_str;
}
