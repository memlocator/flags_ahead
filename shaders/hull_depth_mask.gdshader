shader_type spatial;
// When the camera is inside the hull, writes DEPTH = 1.0 (nearest clip plane) so
// the ocean always fails the depth test at those pixels.
// When the camera is outside, discards every fragment — no depth write, ocean unaffected.
render_mode blend_mix, depth_draw_always, cull_disabled, unshaded, shadows_disabled;

uniform bool camera_inside = false;

void fragment() {
	ALPHA  = 0.0;
	// Inside: poison depth so ocean always fails the test here.
	// Outside: write real geometry depth — blocks ocean seen through the open hull
	//          from above without affecting the exterior waterline.
	DEPTH  = camera_inside ? 1.0 : FRAGCOORD.z;
}
