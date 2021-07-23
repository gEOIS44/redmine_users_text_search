$(function(){
  $('select[id^=operators]').each(function(){
    hideFilterTextbox($(this));
  });

  $(document).on('focusin', 'select[id^=operators]', function(){
    var field = $(this).attr('name').replace(/^op\[(.*)\]$/g, '$1');
    var filterOptions = availableFilters[field];
    if('original_type' in filterOptions && filterOptions['original_type'] != 'user'){
      $(this).children('option[value="me"]').remove();
      $(this).children('option[value="ot"]').remove();
      $(this).children('option[value="~~"]').remove();
    }else{
      $(this).children('option[value="*~"]').remove();
    }
  });

  $(document).on('change', 'select[id^=operators]', function(){
    hideFilterTextbox($(this));
  });

  $(document).on('change', 'input[id^=cb_]', function(){
    hideFilterTextbox($(this).parent().parent().find('select[id^=operators]'));
  });
});

function hideFilterTextbox(element){
  var display = 'block';
  switch(element.val()){
  case 'me':
  case 'ot':
    display = 'none';
  }
  element.parent().parent().find('input[type="text"]').css('display', display);

  if(element.val() == '~~'){
    element.parent().parent().find('input[type="text"]').attr('placeholder', "");
  }else{
    element.parent().parent().find('input[type="text"]').removeAttr('placeholder');
  }
}
