1.	New dataset
Collect public transport images that show handrails/grabrails, especially at train stations, bus stops, ramps, stairs,
and platforms. The images need labels.

2.	Train another model or make the current model multi-class
There are two options:
•	Easier option: train a second model only for handrails/grabrails. 
•	Better option: update the current segmentation model to detect more than one class, for example: 
class 0: background 
class 1: tactile flooring 
class 2: handrail/grabrail 

3.	Add DSAPT checking logic
The current code already calculates luminance contrast between the detected tactile area and the surrounding floor. 

4.	Update function.py
The person needs to add:
•	a new model path, for example HANDRAIL_MODEL_PATH 
•	a new function like run_handrail_model_on_image() 
•	a new function like get_dsapt_handrail_compatibility() 
•	output fields such as has_handrail, handrail_contrast_percentage, and handrail_compatibility_label 

5.	Update the API response
In main.py, the /analyze endpoint currently returns tactile flooring results only, such as compatibility label, contrast percentage,
notes, input image, output image, and PDF report. It needs to return the new handrail result too.

6.	Update the PDF report
The report should show both:
•	Accessibility feature detected: tactile flooring 
•	Additional feature detected: handrail/grabrail 
•	DSAPT contrast result for each feature 

7.	Update the frontend
The frontend should display the new result, for example:
“Handrail detected: Yes”
“Estimated contrast: 34%”
“DSAPT compatibility: Compatible / Not compatible”

