import serial
import pygame
import sys
import threading
import time
import os

os.environ['SDL_VIDEO_WINDOW_POS'] = "%d,%d" % (100, 100)

WIN_W, WIN_H = 800, 800
GRID_SIZE = 16
CELL_W = WIN_W // GRID_SIZE
CELL_H = WIN_H // GRID_SIZE

pygame.init()
try:
    screen = pygame.display.set_mode((WIN_W, WIN_H), pygame.SCALED | pygame.FULLSCREEN)
except Exception as e:
    screen = pygame.display.set_mode((WIN_W, WIN_H))
pygame.display.set_caption("Snake Game Console (FPGA)")

COLOR_MAP = {
    0: (0, 0, 0),        # Background
    1: (0, 255, 0),      # Snake body
    2: (255, 0, 0),      # Apple
    3: (255, 255, 0),    # Snake head
}

display_grid = [[0 for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]
ser = None
running = True

def serial_thread():
    global ser
    try:
        ser = serial.Serial('COM7', 921600, timeout=1)
        print("[OK] Connected to COM7 @ 921600 baud")
    except Exception as e:
        print(f"[ERR] Cannot open COM7: {e}")
        return

    sync_state = 0
    while running:
        if ser.in_waiting > 0:
            b = ser.read(1)[0]
            if sync_state == 0 and b == 0xCC:
                sync_state = 1
            elif sync_state == 1:
                if b == 0xDD:
                    sync_state = 2
                else:
                    sync_state = 0
            elif sync_state == 2:
                game_id = b
                sync_state = 3
            elif sync_state == 3:
                pixel_color = b
                sync_state = 4
            elif sync_state == 4:
                pixel_addr = b
                px = pixel_addr & 0x0F
                py = (pixel_addr >> 4) & 0x0F
                if px < 16 and py < 16:
                    display_grid[py][px] = pixel_color
                sync_state = 0
        else:
            time.sleep(0.001)

t = threading.Thread(target=serial_thread, daemon=True)
t.start()

def send_cmd(cmd):
    if ser and ser.is_open:
        ser.write(bytes([cmd, 0xBB, 0xAA]))

clock = pygame.time.Clock()
while running:
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                running = False
            elif event.key == pygame.K_w or event.key == pygame.K_UP:
                send_cmd(3) 
            elif event.key == pygame.K_a or event.key == pygame.K_LEFT:
                send_cmd(1) 
            elif event.key == pygame.K_s or event.key == pygame.K_DOWN:
                send_cmd(4) 
            elif event.key == pygame.K_d or event.key == pygame.K_RIGHT:
                send_cmd(2) 
            elif event.key == pygame.K_SPACE or event.key == pygame.K_RETURN or event.key == pygame.K_r:
                send_cmd(5) 

    screen.fill((20, 20, 20))

    # Grid offset
    offset_x = (WIN_W - (GRID_SIZE * CELL_W)) // 2
    offset_y = (WIN_H - (GRID_SIZE * CELL_H)) // 2

    for y in range(GRID_SIZE):
        for x in range(GRID_SIZE):
            color = COLOR_MAP.get(display_grid[y][x], (0, 0, 0))
            rect = (offset_x + x * CELL_W, offset_y + y * CELL_H, CELL_W, CELL_H)
            pygame.draw.rect(screen, color, rect)
            pygame.draw.rect(screen, (40, 40, 40), rect, 1) # Border

    pygame.display.flip()
    clock.tick(60)

if ser:
    ser.close()
pygame.quit()
sys.exit(0)
