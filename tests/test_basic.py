"""
Basic tests for pyopensim
"""
def test_import():
    """Test that pyopensim can be imported."""
    import pyopensim as osim
    assert osim is not None

def test_pyopensim_version():
    """Test that the version of pyopensim can be retrieved."""
    import pyopensim as osim
    version = osim.__version__
    assert isinstance(version, str)
    assert len(version) > 0

def test_opensim_model_import():
    """Test that OpenSim Model can be imported and instantiated."""
    from pyopensim.simulation import Model
    
    # Test that we can create a basic model
    model = Model()
    assert model is not None
    
    # Test basic model operations
    model.setName("TestModel")
    assert model.getName() == "TestModel"