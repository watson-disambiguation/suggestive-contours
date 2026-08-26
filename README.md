# Adaptive Selector for Suggestive Contours

In order to use this project, first any models you use must have the compute curvature script applied from the selector support scripts repository, 
also available on my Github. The models need to be imported as a single model and also need to have the curvature_source shader applied to them.
In order to apply suggestive contours, a world environment needs to be created. It needs to have an environment, the settings on it do not matter,
and a compositor, which should contain the compositor effect called SuggestiveContours. Once this is done you can then configure the parameters.
There is a default scene that already has all of this set up you can use as a reference.
