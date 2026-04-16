#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z =1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;
layout(rgba16f, binding = 1, set = 0) uniform image2D normal_tex;
layout(binding = 2, set = 0) uniform sampler2D depth_tex;


layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    float inv_proj_2w;
    float inv_proj_3w;
    float threshold;
} p;

vec3 sample_normals(ivec2 pixel) {
    vec3 normal_raw = imageLoad(normal_tex, pixel).rgb;
    return normalize(normal_raw.rgb * 2.0 - 1.0);
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

    vec4 original_color = imageLoad(screen_tex, pixel);
    vec4 color = vec4(0.);
    color.r = laplacian_depth(pixel,1);
    color.b = laplacian_normals(pixel,1);

    imageStore(screen_tex,pixel,color);
}