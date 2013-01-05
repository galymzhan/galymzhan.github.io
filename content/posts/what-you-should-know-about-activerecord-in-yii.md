---
title: What you should know about ActiveRecord in Yii
created_at: 2012-12-10 22:11
kind: article
published: false
description: What you should know about ActiveRecord in Yii
---

Yii's CActiveRecord is a very nice implementation of Martin Fowler's Active Record pattern. I think it's one of the best features of Yii. It nicely handles validation, persistence and querying of the objects stored in a database, so you can focus on the actual logic instead. Here are some things I wanted to highlight that I think you should know about.


## It's a finder

Instead of talking about CActiveRecord objects in general, let's take `Post` class as an example AR model.

Besides representing your marvelous blog posts, each `Post` object also acts as a finder of posts. When you call `Post::model()` you get a special instance of `Post` which serves as a finder among other things. This is also highlighted in the documentation:

> It is provided for invoking class-level methods (something similar to static class methods.)

It's explicitly stated that returned object should be used to invoke class-level methods, that is, methods which work on collections of `Post` objects rather than one specific instance of `Post`. why not Post::find ?
All `find*` methods are class-level methods because they operate on collection.

To act as a finder, all `Post` objects hold criteria object inside them - instance of `CDbCriteria`. Let's call it *inner criteria* and that's what you get when you call `$post->getDbCriteria()`. When you call various scopes you're actually modifying inner criteria (that's why I like to think about scopes as *criteria modifiers*). Relational query methods like `together` and `with` also modify it. When we initially do `Post::model()`, inner criteria is clean, that is, it does not have any SQL conditions applied. When we further chain scopes like `Post::model()->published()->recent()` criteria gets modified and remembers all query details like condition, ordering, limit, joins, etc (provided we properly wrote these scopes). Finally, when we fire off one of the `find*` or `count*` methods, the actual database query is performed and inner criteria is reset to clean state. The last step is very important, because if criteria isn't reset, all subsequent queries will still be using old criteria details.

So here comes the tricky part - this inner criteria is shared by ALL finder instances of `Post`. Let's have a look at this example to understand why it matters.

```php?start_inline
// Model
class Post extends CActiveRecord {
  // Scopes inside Post model
  public function scopes()
  {
    return array(
      'published' => array(
        'condition' => 'published = 1'
      ),
      'popular' => array(
        'condition' => 'published = 1',
        'order' => 'view_count DESC',
        'limit' => 3,
      ),
    );
  }
  // ...
}

// Controller
class PostController extends CController {
  // Show off posts
	public function actionIndex()
	{
		$dataProvider=new CActiveDataProvider(Post::model()->published()); // Only published, please
		$this->render('index',array(
			'dataProvider'=>$dataProvider,
		));
	}
}

// View
<h1>Posts</h1>

<?php
$this->widget('zii.widgets.CListView', array(
	'dataProvider'=>$dataProvider,
	'itemView'=>'_view',
));
?>
```

So far everything is great. When we go to `/post/index` we see all published blog posts. Now suppose we also want to show latest popular posts. Let's use named scope `popular` for that. Our controller and view will be changed a bit.

```php
// Controller
class PostController extends CController {
  // Show off posts
	public function actionIndex()
	{
		$dataProvider=new CActiveDataProvider(Post::model()->published());
    $popular = Post::model()->popular()->findAll(); // <-- this
		$this->render('index',array(
			'dataProvider'=>$dataProvider,
      'popular' => $popular,
		));
	}
}

// View
<h1>Popular</h1>
<ul>
<? foreach ($popular as $post): ?>
  <li><?= CHtml::encode($post->title) ?></li>
<? endforeach ?>
</ul>

<h1>Posts</h1>
<?php
$this->widget('zii.widgets.CListView', array(
	'dataProvider'=>$dataProvider, // $dataProvider->getData()
	'itemView'=>'_view',
));
?>
```

Now when we go the posts page, we suddenly see ALL posts, both published and not published. Seems like `Post::model()->published()` isn't working when we pass it to the `CActiveDataProvider`. Why? Remember that inner criteria object is shared among all `Post` finders? When we pass `Post::model()->published()` to the provider, the actual database query isn't performed, because `findAll` is NOT called yet (it will be called when `CListView` inside the view gets rendered). When we call `Post::model()->popular()->findAll()`, criteria object inside `Post` is *reset*. So all `Post` finders, including the one which is inside provider, now have a clean criteria. When the CListView gets rendered, it's too late, criteria is already clean, so the finder fetches all posts. To overcome this, we can either get popular posts before creating data provider:

```php
$popular = Post::model()->popular()->findAll();
$dataProvider=new CActiveDataProvider(Post::model()->published());
```

or in case of some complicated scenario we can save and restore the inner criteria:

```php
$dataProvider=new CActiveDataProvider(Post::model()->published());
// Save criteria
$oldCriteria = Post::model()->getDbCriteria();
// Do our work
$popular = Post::model()->popular()->findAll();
// Restore criteria
Post::model()->setDbCriteria($oldCriteria);
```

I believe this shouldn't be common, but you'd better keep it in mind. Now let's take a peek inside CActiveRecord to understand why criteria it shared:

```php
	public static function model($className=__CLASS__)
	{
		if(isset(self::$_models[$className]))
			return self::$_models[$className];
		else
		{
			$model=self::$_models[$className]=new $className(null);
			$model->_md=new CActiveRecordMetaData($model);
			$model->attachBehaviors($model->behaviors());
			return $model;
		}
	}
```

Wow, actually the whole static model is cached in a static variable `$_models` to make things faster, so that means we get the same instance when we call `Post::model()`. Which of course implies that inner criteria will be same too.

## Filtering based on relations


## Using scopes safely
