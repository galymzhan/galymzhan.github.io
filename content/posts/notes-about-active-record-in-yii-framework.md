---
title: Notes about Active Record in Yii framework
created_at: 2013-01-06 13:06:55
kind: article
description: Some useful and good to know things I learned about Active Record in Yii.
---

[Yii](http://www.yiiframework.com/) comes with a nice implementation of Martin
Fowler's Active Record pattern.  Being one of the major components of Yii
framework, it nicely handles validation, persistence and querying of the
objects stored in a database, so you can focus on the actual logic instead.
Here are some useful and good to know things for Yii programmers.

## It's a finder

Instead of talking about CActiveRecord objects in general, let's take Post
class as an example of an AR model.

Besides representing your marvelous blog posts, each Post object also acts as
a finder of posts. When you call `Post::model()` you get a special instance of
`Post` which serves as a finder among other things. This is also highlighted in
the documentation:

> It is provided for invoking class-level methods (something similar to static
> class methods.)

It's explicitly stated that returned object should be used to invoke
class-level methods, or roughly speaking, methods which work on collections of
Post objects rather than one specific instance of Post.  All `find*` methods
are class-level methods because they operate on collection.

To act as a finder, all Post objects hold criteria object inside them --
instance of CDbCriteria. Let's call it *inner criteria* and that's what you
get when you call `$post->getDbCriteria()`. When you call various scopes
you're actually modifying inner criteria (that's why I like to think about
scopes as *criteria modifiers*). Relational query methods like `together` and
`with` also modify it. When we initially call `Post::model()`, inner criteria
is clean, that is, it does not have any SQL conditions applied. When we
further chain scopes like `Post::model()->published()->recent()` criteria gets
modified and remembers all query details like condition, ordering, limit,
joins, etc (provided we properly wrote these scopes). Finally, when we fire
off one of the `find*` or `count*` methods (these methods also can receive
additional criteria object which will be merged with the inner criteria), the
actual database query is performed and inner criteria is reset to clean state.
The last step is very important, because if criteria isn't reset, all
subsequent queries will still be using old criteria details.

So here comes the not so obvious part -- this inner criteria is shared by ALL
finder instances of `Post`. Let's have a look at this example to understand
why it matters.

```php?start_inline
// Model: models/Post.php
class Post extends CActiveRecord {
  // Scopes inside Post model
  public function scopes() {
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

// Controller: controllers/PostController.php
class PostController extends CController {
  // Show off posts
  public function actionIndex() {
    // Show only published posts
    $dataProvider=new CActiveDataProvider(Post::model()->published());
    $this->render('index',array(
      'dataProvider'=>$dataProvider,
    ));
  }
}

// View: views/post/index.php
<h1>Posts</h1>

<?php
$this->widget('zii.widgets.CListView', array(
  'dataProvider'=>$dataProvider,
  'itemView'=>'_view',
));
?>
```

So far everything is great. When we go to `/post/index` we see all published
blog posts. Now suppose we also want to show latest popular posts. Let's use
named scope `popular` for that. Our controller and view will be changed a bit.

```php?start_inline
class PostController extends CController {
  // Show off posts
  public function actionIndex() {
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
  'dataProvider'=>$dataProvider,
  'itemView'=>'_view',
));
?>
```

Now when we go the posts page, we suddenly see ALL posts under **"Posts"**
header, both published and not published. Seems like
`Post::model()->published()` isn't working when we pass it to the
`CActiveDataProvider`. Why? Remember that inner criteria object is shared
among all Post finders? When we pass `Post::model()->published()` to the
provider, the actual database query isn't performed, because `findAll` is NOT
called yet (it will be called when CListView inside the view gets rendered).
When we call `Post::model()->popular()->findAll()`, criteria object inside
Post is *reset*. So all Post finders, including the one which sits inside
provider, now have a clean criteria. When the CListView gets rendered, it's
too late, criteria is already clean, so the CActiveDataProvider fetches all
posts. To overcome this, we can either get popular posts before creating data
provider:

```php?start_inline
$popular = Post::model()->popular()->findAll();
$dataProvider=new CActiveDataProvider(Post::model()->published());
```

or in case of some complicated scenario we can save and restore the inner
criteria:

```php?start_inline
$dataProvider=new CActiveDataProvider(Post::model()->published());
// Save criteria
$oldCriteria = Post::model()->getDbCriteria();
// Do our work
$popular = Post::model()->popular()->findAll();
// Restore criteria
Post::model()->setDbCriteria($oldCriteria);
```

I took me some time to figure out what's happening when I first discovered it,
so you'd better keep it in mind.  Now let's take a peek inside CActiveRecord
to understand why criteria it shared:

```php?start_inline
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

Wow, actually the whole static model is cached in a static variable `$_models`
to make things faster, so that means we get the same instance when we call
`Post::model()`. Which of course implies that inner criteria will be the same
too.

## Searching models based on data inside related models

Another thing I had some troubles with is getting related models and, at the
same time, using relational data to filter primary models. Scenario:

1. **A** (primary model) has many **B**-s
2. You want to search **A** and also fetch **all** of it's **B**-s using
`with` option
3. You want to select only some **A**-s based on data in **B**

To illustrate it, let's add tags to posts:

```php?start_inline
class Post {
  public function relations() {
    return array(
      'tags' => array(self::MANY_MANY, 'Tag', 'post_tag(post_id, tag_id)'),
    );
  }
}
```

Note that we use additional table `post_tag` to store `MANY_MANY` relations.

In the post listing we show tags as links:

```php?start_inline
<b>Tagged:</b>
<? foreach ($post->tags as $tag): ?>
<?= CHtml::link(CHtml::encode($tag->name), array('post/index', 'tag' => $tag->name)) ?>,
<? endforeach ?>
```

Now we should output posts for given tag when `/post/index?tag=tagname` is
requested. No problem, we already have a relation for that:

```php?start_inline
if (isset($_GET['tag'])) {
  $posts = Post::model()->published()->findAll(array(
    'with' => array(
      'tags' => array(
        'condition' => 'tags.name = :tagName',
        'params' => array(':tagName' => $_GET['tag']),
      ),
    ),
  ));
}
```

This code correctly finds tagged posts, but has another problem -- only the
requested tag is shown in a list of tags for all found posts. For example, if
we had visited `/post/index?tag=gaming` page, we'd see only "gaming" in
"Tagged:" section of every post, even if they have more tags. This is correct
behavior, as we're explicitly restricting related tags to only those with
specified name. To get all related tags we can introduce an additional join to
filter posts:

```php?start_inline
$posts = Post::model()->published()->findAll(array(
  'with' => 'tags', // or 'with' => array('tags' => array('together' => false)),
                    // to load tags in a separate query

  // Introducing manual join
  'join' => '
    INNER JOIN post_tag pt ON pt.post_id = t.id
    INNER JOIN tag ON pt.tag_id = tag.id
  ',
  // and specify criteria for the join
  'condition' => 'tag.name = :tagName',
  'params' => array(':tagName' => $_GET['tag']),
));
```

Note that if you don't want to load related models, there is no need in an
additional join, just use the `select` option:

```php?start_inline
// We don't need to load tags
$posts = Post::model()->published()->findAll(array(
  'with' => array(
    'tags' => array(
      'select' => false,
      'condition' => 'tags.name = :tagName',
      'params' => array(':tagName' => $_GET['tag']),
    ),
  ),
));
```

## Using scopes safely

Scopes are great. They allow us to refactor monstrous `find*` invocations and
break them into simple, maintainable and reusable methods.

Since all AR query stuff eventually gets converted into SQL equivalent, most
errors arise from naming conflicts. We don't need to worry about it when
calling one of the AR query methods with additional criteria parameter, since
we see all table, column names and aliases right where the call happens. But
when writing scopes, we should take extra measures to prevent errors. This is
because we don't know in advance all the places where this scope is going to
be used, so we must ensure there isn't anything hardcoded.

### Quote table, alias and column names

```php?start_inline
// Bad
$this->getDbCriteria()->mergeWith(array(
  'condition' => 't.likes > 10',
));

// Good
$db = $this->getDbConnection();
$alias = $this->getTableAlias(true); // Pass true to quote
$column = $db->quoteColumnName('likes');
$this->getDbCriteria()->mergeWith(array(
  'condition' => "{$alias}.{$column} > 10",
));
```

### Table alias

As noted in the documentation, table alias may vary in relational queries, so
we don't know it in advance. The good example is already shown above.

```php?start_inline
// Bad, does not use alias at all
$column = $db->quoteColumnName('likes');
$this->getDbCriteria()->mergeWith(array(
  'condition' => "{$column} > 10",
));

// Bad, hardcoded alias
$this->getDbCriteria()->mergeWith(array(
  'condition' => "t.{$column} > 10",
));
```

### Table names

If you'll ever need to know name of a table, all AR models define method
"tableName".

```php?start_inline
// Bad
$this->getDbCriteria()->mergeWith(array(
  'join' => 'user',
));

// Good
$db = $this->getDbConnection();
$table = $db->quoteTableName(User::model()->tableName());
$this->getDbCriteria()->mergeWith(array(
  'join' => $table,
));
```

### Use unique names for binding parameters

We could have invented our own solution for this, but CDbCriteria already
provides static `$paramCount` property, which is used internally by framework
itself to generate unique parameter names.

```php?start_inline
// Bad, this fails if there is another binding called :param
$criteria->mergeWith(array(
  'condition' => "t.id > :param",
  'params' => array(':param' => 2),
));

// Good
// By default it generates names like :ycp1
$paramName = CDbCriteria::PARAM_PREFIX . CDbCriteria::$paramCount++;
$criteria->mergeWith(array(
  'condition' => "t.id > {$paramName}",
  'params' => array($paramName => 2),
));
```

### Merge default scopes of parent classes

If both child and parent AR classes have defined defaultScope, do not try to
merge them with something like `array_merge`, use `CDbCriteria::mergeWith`
instead:

```php?start_inline
public function defaultScope() {
  $criteria = new CDbCriteria(array(
    // Specify your default scope here
  ));
  $criteria->mergeWith(parent::defaultScope());
  return $criteria;
}
```

# Also ...

You should be able to debug AR stuff by looking at generated SQLs. I use
CWebLogRoute to see all SQL queries at the bottom of a page, so I can quickly
search. If you can't find your query just use some unique alias or SQL comment
(like "abracadabra") and search for that.

Of course we can fall back to SQL, but AR is much more convenient to use over
plain arrays, especially if models contain complicated business logic.
Also, some components like CActiveDataProvider work only with AR.
