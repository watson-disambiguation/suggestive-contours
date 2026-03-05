#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z =1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;
layout(rgba16f, binding = 1, set = 0) uniform image2D normal_tex;
layout(binding = 2, set = 0) uniform sampler2D depth_tex;


layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    float radius;
    float s;
    float d;
    float inv_proj_2w;
    float inv_proj_3w;
    float normal_threshold;
    float depth_threshold;
} p;

vec3 sample_normals(ivec2 pixel) {
    vec3 normal_raw = imageLoad(normal_tex, pixel).rgb;
    return normalize(normal_raw.rgb * 2.0 - 1.0);
}

float get_diffuse_lit_from_camera(ivec2 pixel) {
    vec3 normal = sample_normals(pixel);
    if (normal.z < -0.5) {
        return 1.0;
    }
    return normal.z;
}
// returns 1 if valley, 2 if peak, 0 if neither and -1 if background;
int is_valley_or_peak(ivec2 pixel, int radius, float s, float d) {
    float p_max = -1.0;
    float p_min = 2.0;
    int count = 0;
    int count_darker = 0;
    int count_lighter = 0;
    float center_val = sample_normals(pixel).z;
    if (center_val < -0.5) {
        return -1;
    }
    for (int x_offset = -radius; x_offset <= radius; x_offset++) {
        for (int y_offset = -radius; y_offset <= radius; y_offset++) {
            // check for circular space
            if (x_offset * x_offset + y_offset * y_offset > radius * radius) {
                continue;
            }
            count++;
            float val = get_diffuse_lit_from_camera(pixel + ivec2(x_offset,y_offset));
            p_max = max(p_max,val);
            p_min = min(p_min,val);
            if (val < center_val) {
                count_darker++;
            }
            if (val > center_val) {
                count_lighter++;
            }
        }
    }

    float portion_darker =  float(count_darker) / float(count);
    float portion_lighter =  float(count_lighter) / float(count);
    float diff_from_max = p_max - center_val;
    float diff_from_min = center_val - p_min;
    if (portion_darker < s && diff_from_max > d) {
        return 1;
    }
    if (portion_lighter < s && diff_from_min > d) {
        return 2;
    }
    return 0;
}

float sample_depth(ivec2 pixel) {
    vec2 uv = pixel / p.screen_size;
    float depth = texture(depth_tex,uv).r;
    float linear_depth = 1. / (depth * p.inv_proj_2w + p.inv_proj_3w);
    return linear_depth;
}

float laplacian_depth(ivec2 center, int radius) {
    float value = 0;
    int diameter = 2 * radius + 1;
    float center_value = float(diameter * diameter - 1);
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            float weight = (y == 0 && x == 0) ? center_value : -1.;
            value += weight * sample_depth(center + ivec2(x,y));
        }
    }
    return value;
}

float laplacian_normals(ivec2 center, int radius) {
    vec3 value = vec3(0.);
    int diameter = 2 * radius + 1;
    float center_value = float(diameter * diameter - 1);
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            float weight = (y == 0 && x == 0) ? center_value : -1.;
            value += weight * sample_normals(center + ivec2(x,y));
        }
    }
    return max(value.r,max(value.g,value.b));
}

void main() {

    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    vec2 size = p.screen_size;

    if (pixel.x >= size.x || pixel.y >= size.y) return;

    vec4 original_color = imageLoad(screen_tex,pixel);
    vec4 color = vec4(1.0);
    // starting using greyscale, just use G for now
    float shading = original_color.g;
    float threshold = 0.2;

    vec3 line_color_valley = vec3(0.0);
    vec3 line_color_peak = vec3(1.0);
    vec3 fill_color = vec3(0.5);
    vec3 background_color = vec3(1.0);

    vec3 dark_color = vec3(0.0);
    vec3 light_color = vec3(1.0);
    
    int contour_status = is_valley_or_peak(pixel,int(p.radius),p.s,p.d);
    switch (contour_status) {
        case 0:
        case 2:
            color.rgb = fill_color;
            break;
        case 1: 
            color.rgb = line_color_valley;
            break;
        default:
            color.rgb = background_color;
    }
    if (laplacian_depth(pixel,1) > p.depth_threshold) {
        color.rgb = line_color_valley;
    }
    if (laplacian_normals(pixel,1) > p.normal_threshold) {
        color.rgb = line_color_valley;
    }

    imageStore(screen_tex,pixel,color);
}