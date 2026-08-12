shader_type canvas_item;

// 视野角度：数值越小，透视越强；卡牌建议先从 45～70 开始。
uniform float fov : hint_range(1.0, 179.0) = 55.0;

// 是否裁掉翻到背面的卡面。
uniform bool cull_back = true;

// 左右 / 上下倾斜角度。
uniform float y_rot : hint_range(-180.0, 180.0) = 0.0;
uniform float x_rot : hint_range(-180.0, 180.0) = 0.0;

// 防止旋转后边缘被裁切。
// 0：静止时保持原尺寸。
// 1：预留更大安全区域，旋转更不容易裁边。
uniform float inset : hint_range(0.0, 1.0) = 0.18;

varying flat vec2 perspective_offset;
varying vec3 perspective_position;


void vertex() {
	float sin_y = sin(y_rot / 180.0 * PI);
	float cos_y = cos(y_rot / 180.0 * PI);
	float sin_x = sin(x_rot / 180.0 * PI);
	float cos_x = cos(x_rot / 180.0 * PI);

	mat3 inverse_rotation;
	inverse_rotation[0][0] = cos_y;
	inverse_rotation[0][1] = 0.0;
	inverse_rotation[0][2] = -sin_y;

	inverse_rotation[1][0] = sin_y * sin_x;
	inverse_rotation[1][1] = cos_x;
	inverse_rotation[1][2] = cos_y * sin_x;

	inverse_rotation[2][0] = sin_y * cos_x;
	inverse_rotation[2][1] = -sin_x;
	inverse_rotation[2][2] = cos_y * cos_x;

	float perspective = tan(fov / 360.0 * PI);

	perspective_position = inverse_rotation * vec3(UV - 0.5, 0.5 / perspective);

	float viewport_distance = (0.5 / perspective) + 0.5;
	perspective_position.xy *= viewport_distance * inverse_rotation[2].z;
	perspective_offset = viewport_distance * inverse_rotation[2].xy;

	// 按纹理像素尺度扩展顶点，避免旋转时裁边。
	VERTEX += (UV - 0.5) / TEXTURE_PIXEL_SIZE * perspective * (1.0 - inset);
}

void fragment() {
	if (cull_back && perspective_position.z <= 0.0) {
		discard;
	}

	vec2 uv = (perspective_position.xy / perspective_position.z) - perspective_offset;

	COLOR = texture(TEXTURE, uv + 0.5);

	// 防止采样到卡牌区域外。
	COLOR.a *= step(max(abs(uv.x), abs(uv.y)), 0.5);
}