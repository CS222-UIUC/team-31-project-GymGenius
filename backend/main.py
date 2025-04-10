import cv2
import os
import shutil
from fastapi import FastAPI


@app.post("/record")
def recording():
    camera = cv2.VideoCapture(0) #Sets up the camera
    camera.set(cv2.CAP_PROP_FRAME_WIDTH, 1920) # Makes camera makes resolution
    camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
    camera.set(cv2.CAP_PROP_FPS, 20)  # Try reducing FPS
    mp4 = cv2.VideoWriter_fourcc(*'avc1') #outputs an mp4 file
    out = cv2.VideoWriter('output.mp4', mp4, 30.0, (1920,1080))
    while camera.isOpened():
        ret, frame = camera.read()
        if not ret: #if the camera is not reading anything just break out of the for loop
            break
        out.write(frame) 
        cv2.imshow('Recording', frame)

        if cv2.waitKey(1) & 0xFF == ord('q'): #Ends when user presses q
            break

    camera.release()
    out.release()
    cv2.destroyAllWindows()
    return {"message": "recorded"}


@app.post("/frames")
def framesInVideo():

    if os.path.exists("frames"):
        shutil.rmtree("frames")


    os.makedirs("frames", exist_ok = True)
    recording = cv2.VideoCapture("output.mp4")
    frames_count = 1
    while recording.isOpened():
        ret, frame = recording.read()
        if not ret: #if the camera is not reading anything just break out of the for loop
            break
            
        if frames_count % 15 == 0:
            frame_filename = os.path.join("frames", f"frames_{frames_count}.jpg")
            cv2.imwrite(frame_filename, frame)
        frames_count += 1
    recording.release()
    cv2.destroyAllWindows()
    return {"message": f"{count} frames checked"}








