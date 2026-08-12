# ============================================
# RoundedRectGenerator.gd
# 像素风格圆角矩形生成器（单脚本）
# 用法：RoundedRectGenerator.generate(64, 64, 8, Color.WHITE)
# ============================================

class_name RoundedRectGenerator
extends RefCounted

# 生成圆角矩形纹理
static func generate(width: int, height: int, radius: int, color: Color) -> ImageTexture:
	# 参数限制
	radius = clampi(radius, 0, min(width, height) / 2)
	
	# 创建图像
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# 遍历每个像素
	for x in range(width):
		for y in range(height):
			if _is_inside_rounded_rect(x, y, width, height, radius):
				image.set_pixel(x, y, color)
	
	# 返回纹理
	return ImageTexture.create_from_image(image)

# 判断像素是否在圆角矩形内
static func _is_inside_rounded_rect(x: int, y: int, w: int, h: int, r: int) -> bool:
	# 如果在中心矩形区域，直接返回true
	if x >= r and x < w - r and y >= r and y < h - r:
		return true
	
	# 检查四个角（只检查在角区域的像素）
	# 左上角
	if x < r and y < r:
		return (x - r) * (x - r) + (y - r) * (y - r) <= r * r
	# 右上角
	if x >= w - r and y < r:
		return (x - (w - r)) * (x - (w - r)) + (y - r) * (y - r) <= r * r
	# 左下角
	if x < r and y >= h - r:
		return (x - r) * (x - r) + (y - (h - r)) * (y - (h - r)) <= r * r
	# 右下角
	if x >= w - r and y >= h - r:
		return (x - (w - r)) * (x - (w - r)) + (y - (h - r)) * (y - (h - r)) <= r * r
	
	# 在矩形边缘但不在角区域（垂直/水平边）
	return true
