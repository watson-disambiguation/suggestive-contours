shader_type spatial;
render_mode unshaded;
uniform float curvature_scale = 1.;
uniform bool display_curvature = false;
varying float curvature_view_alignment;
varying float object_scale;
void vertex() {
	vec3 model_curve_dir = 2. * COLOR.xyz - 1.;
	vec3 world_curve_dir = normalize(model_curve_dir * MODEL_NORMAL_MATRIX).xyz;
	vec3 world_normal = normalize(NORMAL * MODEL_NORMAL_MATRIX);
	vec3 tangent_view_dir = normalize(CAMERA_DIRECTION_WORLD - dot(CAMERA_DIRECTION_WORLD,world_normal) * world_normal);
	curvature_view_alignment = dot(world_curve_dir,tangent_view_dir);
	curvature_view_alignment *= curvature_view_alignment;
	object_scale = length(MODEL_MATRIX[0].xyz);
}

void fragment() {
	float directional_curvature = UV2.x * curvature_view_alignment + UV2.y * (1. - curvature_view_alignment);
	directional_curvature /= object_scale;
	float c = abs(directional_curvature) * curvature_scale;
	if (display_curvature) {
		ALBEDO = directional_curvature > 0. ? vec3(0.,c,0.) : vec3(c,0.,0.); 
	}
	ROUGHNESS = clamp(0.5 * directional_curvature * curvature_scale + 0.5,0.,1.);
}